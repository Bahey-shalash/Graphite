# App shell: workspace model, root view, sidebar, tabs, panes, commands, settings (SHELL)
Snapshot: b13dec3 (main, 2026-10-18).
Scope: `App/GraphiteApp.swift` and 31 files in `Sources/GraphiteUI/` (listed in section 2), 32 files, 11,099 physical lines, 8,942 code lines (method: blank and comment-only lines and string contents removed by the reconnaissance script). `WorkspaceModel` extensions that live in other areas' files (13 files) were read for the responsibility map and are cited but not counted in the scope totals.

| Principle | Verdict | Reason |
| --- | --- | --- |
| S | Weak | `WorkspaceModel` has 86 stored properties and 74 functions in its main file, plus 22 more extension files; about 15 responsibilities share one object. `GraphiteRootView` holds 16 state properties and 12 presentations. |
| O | Weak | A new document kind touches 13 UI files plus `DocumentKind`. 27 commands are declared twice (palette and menu bar). Three `default:` branches over `DocumentKind` hide new kinds. |
| L | Mixed | Most substitutions hold. Failed reads show as empty lists in 4 places. Reading a note aloud has two implementations that disagree. One function returns no highlights on the Mac. |
| I | Weak | 51 view declarations in scope take the whole `WorkspaceModel` (grep `(var|let) workspace: WorkspaceModel`). `CommunityPluginHost` holds a back-reference and reads about 23 of its members. `store`, `index`, `folderAccess` and `layout` are settable from anywhere. |
| D | Weak | `WorkspaceModel` builds its own preferences, vault library, recorder, plugin host and conflict store. Per-vault state goes to `UserDefaults.standard` under 5 concatenated key families. 16 `.shared` uses and 3 mutable statics. |
| Clean code | Mixed | Comments state reasons and names are explicit; pure helpers are tested. But 29 functions exceed 40 code lines (`GraphiteRootView.body` 172), 82 assignments go to one `errorMessage` string, sleeps act as ordering or polling 5 times, and 8 kinds of logic are duplicated. |

## 1. Summary

**What the area does.** The shell is everything between the app entry point and the document editors. `GraphiteApp` builds one `GraphiteRootView` (iPad, iPhone) or `GraphiteMacScenes` (Mac). The root view owns window layout: a split view with the sidebar, the documents area, the links inspector, focus mode, palettes, and every sheet. The single `@Observable` `WorkspaceModel` holds the rest:
- the open vault and switching between vaults;
- indexing, search and external-change refresh;
- tabs and the split, and loading documents into tabs;
- file management, attachments, drawings and recordings;
- conflict versions, bookmarks, templates, appearance and theme;
- the community plugin host.

`VaultSidebar` shows the file tree (AppKit's outline view on the Mac), search results, and the Tags, Properties and Bookmarks panels. `WorkspacePanes` shows one or two groups of tabs. `WorkspaceCommandList` (palette) and `GraphiteCommands` (menu bar) are the commands. `SettingsView` and `GraphitePreferences` are the settings.

**The three biggest problems.**
1. **One aggregate for the whole app.** `WorkspaceModel` declares 86 stored properties across 5 places in its main file. It is spread over 23 files and carries about 15 responsibilities. A vault switch resets about 30 of those fields by hand in one 80-line function ([WorkspaceModel.swift:267-346](../../../Sources/GraphiteUI/WorkspaceModel.swift#L267-L346)). Seventy view declarations in the UI module take the whole object. It cannot be built without `UserDefaults.standard`, the real recorder and the real plugin host, so its tests save and restore the process's preferences ([UiWorkspaceModelFixTests.swift:17-37](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L17-L37)).
2. **Features are wired in by hand at many places.**
   - Adding the canvas document kind touched 13 UI files (section 4, OCP-SHELL-01).
   - 27 commands exist twice, once in each command registry.
   - The vault-removal cleanup names five kinds of per-vault state by hand and misses folded headings (BUG-SHELL-02).
   - Three `default:` branches over `DocumentKind` hide new kinds from the compiler.
3. **One string slot reports outcomes.** 82 assignments write `WorkspaceModel.errorMessage` (grep `errorMessage = ` over `Workspace*.swift`, 84 matches, two of which set a PDF session's message). The last writer wins, sheets have to re-host the alert, and errors are prose built inside the model. The same pattern swallows a failed save when the Mac quits (BUG-SHELL-03).

**The three best parts.**
1. **Pure, tested decision helpers inside the model:**
   - `ExternalChangeRefresh` and `externalRefreshDeadline` ([WorkspaceModel.swift:1281-1283](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1281-L1283), [1405-1453](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1405-L1453));
   - `insertionRange` ([WorkspaceModel.swift:904-912](../../../Sources/GraphiteUI/WorkspaceModel.swift#L904-L912));
   - `TabLayout` as a Core value type with the model's derived fields projected from it ([WorkspaceModel.swift:40-52](../../../Sources/GraphiteUI/WorkspaceModel.swift#L40-L52)).

   All are pinned by tests ([UiWorkspaceModelFixTests.swift:237-258](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L237-L258), [346-364](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L346-L364), [527-550](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L527-L550)).
2. **Data-safety workflows that never lose typed text:**
   - text typed during a move is saved at the new place, or as a ` Graphite edits` copy ([WorkspaceFileManagement.swift:206-228](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L206-L228));
   - a tab closes only after its save succeeds ([WorkspaceTabs.swift:226-239](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L226-L239));
   - an embed is refused, never forced, when its note closed or conflicts ([WorkspaceModel.swift:875-891](../../../Sources/GraphiteUI/WorkspaceModel.swift#L875-L891));
   - a vault switch saves twice around its waits ([WorkspaceModel.swift:289-302](../../../Sources/GraphiteUI/WorkspaceModel.swift#L289-L302)).
3. **Small, injectable stores with hermetic tests.** `VaultLibrary` keeps entries it cannot decode instead of overwriting them ([VaultLibrary.swift:67-109](../../../Sources/GraphiteUI/VaultLibrary.swift#L67-L109)). `DocumentPlaceStore` takes its `UserDefaults` ([WorkspacePlaces.swift:79-112](../../../Sources/GraphiteUI/WorkspacePlaces.swift#L79-L112)). The conflict-version feature has its own model, wording enum and injected `ConflictVersionStore` ([ConflictVersionsSheet.swift:8-65](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L8-L65), [WorkspaceModel.swift:165](../../../Sources/GraphiteUI/WorkspaceModel.swift#L165)). The tests use private defaults suites ([DocumentPlaceStoreTests.swift:11-18](../../../Tests/GraphiteUITests/DocumentPlaceStoreTests.swift#L11-L18), [UiFileManagementFixTests.swift:265-272](../../../Tests/GraphiteUITests/UiFileManagementFixTests.swift#L265-L272)).

**Earlier-pass claims checked against the code.**

| Claim (document) | Verdict | Evidence |
| --- | --- | --- |
| `WorkspaceModel` combines vault lifecycle, search/index orchestration, note creation, attachment and drawing insertion, export, recording destinations and external-change handling (`Docs/SOLID.md` at b13dec3) | Holds; understated | All seven are in [WorkspaceModel.swift](../../../Sources/GraphiteUI/WorkspaceModel.swift) (openVault 267, startIndexing 516, createNote 711, saveAttachment 858, exportDrawingCopy 1080, recordingDirectory 1139, scheduleExternalRefresh 1226). Tabs, conflicts, appearance, theme, bookmarks, templates and plugin views were added in extensions since then. |
| "Extract coherent workflows from `WorkspaceModel`" is open work (`Docs/SOLID.md` at b13dec3) | Holds: not done | Attachment publication, recording destination and vault lifecycle still live in the main declaration (lines cited above). |
| New document kinds require changes to classification, tab loading and pane rendering (`Docs/SOLID.md` at b13dec3) | Holds; understated | The canvas kind touches 13 UI files (OCP-SHELL-01), not 3. |
| `WorkspacePanes` and `VaultSidebar` receive the broad workspace object (`Docs/SOLID.md` at b13dec3) | Holds | [WorkspacePanes.swift:23](../../../Sources/GraphiteUI/WorkspacePanes.swift#L23), [VaultSidebar.swift:52](../../../Sources/GraphiteUI/VaultSidebar.swift#L52); 51 such declarations in scope. |
| Preferences and `VaultLibrary` accept a defaults store (`Docs/SOLID.md` at b13dec3) | Holds for the types, not for their use | `init(defaults: UserDefaults = .standard)` at [GraphitePreferences.swift:357](../../../Sources/GraphiteUI/GraphitePreferences.swift#L357) and [VaultLibrary.swift:26](../../../Sources/GraphiteUI/VaultLibrary.swift#L26), but `WorkspaceModel` builds both with the default ([WorkspaceModel.swift:15](../../../Sources/GraphiteUI/WorkspaceModel.swift#L15), [178](../../../Sources/GraphiteUI/WorkspaceModel.swift#L178)). |
| Workspace persistence uses `UserDefaults.standard` directly (`Docs/SOLID.md` at b13dec3) | Holds | 5 uses in [WorkspaceModel.swift](../../../Sources/GraphiteUI/WorkspaceModel.swift#L23), plus [WorkspaceFolds.swift:14](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L14), [WorkspaceTabs.swift:421](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L421), [WorkspaceFileManagement.swift:288](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L288), [WorkspaceBookmarks.swift:83](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L83), [WorkspaceCommands.swift:71](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L71). |
| A file is open in at most one tab ([Architecture.md:125](../../../Docs/Architecture.md)) | Holds | [WorkspaceModel.swift:446-457](../../../Sources/GraphiteUI/WorkspaceModel.swift#L446-L457), [WorkspaceTabs.swift:383-386](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L383-L386). |
| A test can give its workspace a place store of its own ([Architecture.md:126](../../../Docs/Architecture.md)) | Holds, by assignment after construction | `@ObservationIgnored var documentPlaceStore = DocumentPlaceStore.shared` ([WorkspaceModel.swift:69](../../../Sources/GraphiteUI/WorkspaceModel.swift#L69)); not an initializer argument. |
| Recovery copies are deleted with the vault's entry in the vault list ([Architecture.md:129](../../../Docs/Architecture.md)) | Holds | [WorkspaceModel.swift:248-250](../../../Sources/GraphiteUI/WorkspaceModel.swift#L248-L250). |
| The root view queues links until the last vault has reopened ([Architecture.md:135](../../../Docs/Architecture.md)) | Holds | [GraphiteRootView.swift:203-211](../../../Sources/GraphiteUI/GraphiteRootView.swift#L203-L211), [224-226](../../../Sources/GraphiteUI/GraphiteRootView.swift#L224-L226). |
| Mac: one main window and a Settings scene on one `WorkspaceModel` ([Architecture.md:142](../../../Docs/Architecture.md)) | Holds | [GraphiteMacScenes.swift:28-36](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L28-L36). |
| Removing a vault forgets "the folds, recent files, and tabs remembered for it" (code comment [WorkspaceModel.swift:242-243](../../../Sources/GraphiteUI/WorkspaceModel.swift#L242-L243) and test doc [UiWorkspaceModelFixTests.swift:151](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L151)) | Does not hold | Folded-heading records stay (BUG-SHELL-02); the test checks three keys only ([UiWorkspaceModelFixTests.swift:158](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L158)). |

## 2. File inventory

Physical and code lines are the reconnaissance figures (physical lines checked against `read_files`; each file reads one line longer because of the trailing newline).

| File | Physical | Code | Responsibility |
| --- | ---: | ---: | --- |
| [App/GraphiteApp.swift](../../../App/GraphiteApp.swift) | 38 | 24 | App entry: diagnostics, Mac scenes or iPad/iPhone `WindowGroup`, commands, voice-download background task |
| [AppIconSettingsSection.swift](../../../Sources/GraphiteUI/AppIconSettingsSection.swift) | 104 | 97 | iOS alternate app icon picker |
| [ConflictVersionsSheet.swift](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift) | 489 | 406 | Versions sheet: its model, wording, version preview, text comparison rows, banner and marker |
| [FileRecoverySheet.swift](../../../Sources/GraphiteUI/FileRecoverySheet.swift) | 157 | 141 | File recovery browser: notes, snapshots, snapshot preview and restore |
| [FontSettings.swift](../../../Sources/GraphiteUI/FontSettings.swift) | 295 | 248 | Settings › Appearance › Font: font roles, size slider, family picker, system font picker |
| [GraphiteCommands.swift](../../../Sources/GraphiteUI/GraphiteCommands.swift) | 178 | 159 | Menu-bar commands and keyboard shortcuts (`Commands`) |
| [GraphiteMacScenes.swift](../../../Sources/GraphiteUI/GraphiteMacScenes.swift) | 79 | 54 | Mac main window and Settings scene; save-before-quit delegate |
| [GraphitePreferences.swift](../../../Sources/GraphiteUI/GraphitePreferences.swift) | 498 | 387 | Device preferences (36 stored properties), `CorePlugin` and five other preference enums, palette colors, titles for Core enums |
| [GraphiteRootView.swift](../../../Sources/GraphiteUI/GraphiteRootView.swift) | 760 | 623 | Window root: split view, toolbars, palettes, every sheet, deep-link queue, scene lifecycle, drawing-draft recovery; create-document sheet |
| [MacFileTree.swift](../../../Sources/GraphiteUI/MacFileTree.swift) | 517 | 400 | Mac file tree on `NSOutlineView`: nodes, controller, outline view, cell |
| [MessageAlert.swift](../../../Sources/GraphiteUI/MessageAlert.swift) | 68 | 52 | Alert that splits a message into title and detail; notice banner |
| [PresentedScreenObserver.swift](../../../Sources/GraphiteUI/PresentedScreenObserver.swift) | 87 | 56 | Run-loop observer telling a view when a presented screen covers it |
| [QuickPalette.swift](../../../Sources/GraphiteUI/QuickPalette.swift) | 435 | 351 | Palette view, quick switcher, command palette, template picker; `DocumentKind.systemImage`; two environment actions |
| [SettingsView.swift](../../../Sources/GraphiteUI/SettingsView.swift) | 1068 | 950 | Settings navigation and 11 settings pages; `VaultSettingsChanges` serial writer; folder-path normalizer |
| [TabSwitcher.swift](../../../Sources/GraphiteUI/TabSwitcher.swift) | 121 | 110 | Phone tab list sheet; tab count label |
| [VaultLibrary.swift](../../../Sources/GraphiteUI/VaultLibrary.swift) | 132 | 99 | Known-vault list persistence, tolerant of unreadable entries; legacy bookmark adoption |
| [VaultSidebar.swift](../../../Sources/GraphiteUI/VaultSidebar.swift) | 1169 | 952 | Sidebar (picker, search, file tree rows, menus), drag types, file sheets and confirmations, rename/new-folder/move sheets |
| [VaultSidebarPanels.swift](../../../Sources/GraphiteUI/VaultSidebarPanels.swift) | 437 | 365 | `SidebarPanel` enum, Tags/Properties/Bookmarks lists and their loading model |
| [VaultSwitcher.swift](../../../Sources/GraphiteUI/VaultSwitcher.swift) | 353 | 309 | Vault switcher bar and menu, vault manager, new-vault form, `errorAlert` helper |
| [WorkspaceBookmarks.swift](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift) | 97 | 77 | `WorkspaceModel` extension: bookmarks read, change, open, follow moves |
| [WorkspaceCommands.swift](../../../Sources/GraphiteUI/WorkspaceCommands.swift) | 253 | 239 | `WindowActions`; command palette's command list |
| [WorkspaceConflictVersions.swift](../../../Sources/GraphiteUI/WorkspaceConflictVersions.swift) | 193 | 133 | `WorkspaceModel` extension: conflict-version discovery queue and the three decisions |
| [WorkspaceDeepLinks.swift](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift) | 169 | 150 | `WorkspaceModel` extension: `graphite://` link actions |
| [WorkspaceFileManagement.swift](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift) | 317 | 237 | `WorkspaceModel` extension: new folder, rename, move with link updates, copy, delete, reveal |
| [WorkspaceFocusMode.swift](../../../Sources/GraphiteUI/WorkspaceFocusMode.swift) | 24 | 20 | Focus-mode value type remembering panel visibility |
| [WorkspaceModel.swift](../../../Sources/GraphiteUI/WorkspaceModel.swift) | 1471 | 1050 | The workspace aggregate (see section 3); `ExternalChangeRefresh` |
| [WorkspaceMoreMenu.swift](../../../Sources/GraphiteUI/WorkspaceMoreMenu.swift) | 32 | 22 | Workspace commands appended to a document's More menu |
| [WorkspacePanes.swift](../../../Sources/GraphiteUI/WorkspacePanes.swift) | 825 | 687 | Documents area: split, tab bar, tab items, divider, tab content by kind, PDF password prompt, empty tab, window touch observer; `Pasteboard` |
| [WorkspacePlaces.swift](../../../Sources/GraphiteUI/WorkspacePlaces.swift) | 112 | 81 | `WorkspaceModel` extension for document places; `DocumentPlaceStore` |
| [WorkspaceRecovery.swift](../../../Sources/GraphiteUI/WorkspaceRecovery.swift) | 75 | 59 | `WorkspaceModel` extension: file recovery snapshots and restore |
| [WorkspaceTabs.swift](../../../Sources/GraphiteUI/WorkspaceTabs.swift) | 444 | 319 | `TabDocument`; `WorkspaceModel` extension: tab activation, closing, history, loading by kind, layout persistence |
| [WorkspaceTemplates.swift](../../../Sources/GraphiteUI/WorkspaceTemplates.swift) | 102 | 85 | `WorkspaceModel` extension: template files, insertion, daily notes, their settings |
| **Total (32 files)** | **11,099** | **8,942** | |

`WorkspaceModel` extensions outside this scope, read for section 3. Line counts are physical, from `list_files`.

| File | Lines | Members added |
| --- | ---: | --- |
| [WorkspaceAppearance.swift](../../../Sources/GraphiteUI/WorkspaceAppearance.swift) | 130 | vault appearance apply/reload/update/save, font size |
| [WorkspaceTheme.swift](../../../Sources/GraphiteUI/WorkspaceTheme.swift) | 64 | theme refresh and resolution |
| [WorkspaceCanvas.swift](../../../Sources/GraphiteUI/WorkspaceCanvas.swift) | 38 | `canvasSession`, open and create canvas |
| [WorkspaceFolds.swift](../../../Sources/GraphiteUI/WorkspaceFolds.swift) | 55 | per-note folds in `UserDefaults.standard` |
| [WorkspaceGraph.swift](../../../Sources/GraphiteUI/WorkspaceGraph.swift) | 55 | graph cache, open a graph node; `GraphSettingKey` |
| [WorkspaceMap.swift](../../../Sources/GraphiteUI/WorkspaceMap.swift) | 24 | placed-notes cache |
| [WorkspaceImageDrawing.swift](../../../Sources/GraphiteUI/WorkspaceImageDrawing.swift) | 127 | draw on image, Pencil double-tap, embed rewrite |
| [WorkspaceMentions.swift](../../../Sources/GraphiteUI/WorkspaceMentions.swift) | 105 | backlinks and unlinked mentions |
| [WorkspaceTagsAndProperties.swift](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift) | 105 | tags, properties, property rename |
| [WorkspaceReadingTasks.swift](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift) | 32 | tick a task from reading view |
| [WorkspaceRecordingRecovery.swift](../../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift) | 43 | unfinished recordings |
| [LassoTools.swift:72-98](../../../Sources/GraphiteUI/LassoTools.swift#L72-L98) | 27 | lasso picture to note |
| [EditorCompletion.swift:333-343](../../../Sources/GraphiteUI/EditorCompletion.swift#L333-L343) | 11 | write a block identifier into another note |
| [CommunityPluginViews.swift:192-312](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L192-L312) | 121 | plugin views in tabs, layout save/restore of plugin views |

## 3. Responsibility maps of the major types

### 3.1 `WorkspaceModel` (main declaration plus 23 extension blocks in 22 other files)

`grep "extension WorkspaceModel"` finds 24 blocks in 23 files, the main file included. Stored properties are counted by reading [WorkspaceModel.swift:8-209](../../../Sources/GraphiteUI/WorkspaceModel.swift#L8-L209) and the four later declarations at [1011](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1011), [1097-1105](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1097-L1105) and [1277](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1277): **86 stored properties**. Extensions cannot add stored properties, so every feature's state is declared in the main file. `grep func` over the main file finds **74 functions**. `WorkspaceTabs.swift` adds 30 functions and 2 computed properties ([WorkspaceTabs.swift:84-444](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L84-L444)).

| # | Responsibility | Stored state (main file line) | Functions (file:line) |
| --- | --- | --- | --- |
| 1 | Vault lifecycle | `folderAccess` 12, `currentVaultIdentifier` 14, `vaultLibrary` 15, `store` 16, `index` 17, `monitor` 198, `layoutVaultIdentifier` 55 | `openFolderAsVault` 225, `openVault` 229/267, `createVault` 235, `removeFromVaultList` 244, `prepareToLeaveCurrentVault` 261, `vaultFolderDidMove` 352, `restoreVault` 371, `title` 211, `vaultPath(for:)` 1336-1353, `storedPath` 1301 |
| 2 | Obsidian settings of the vault | `vaultSettings` 125, `templateSettings` 141, `dailyNoteSettings` 142 | `reloadVaultSettings` 379, `updateVaultSettings` 394, `refuseBackslash` 774, `newFileDirectory` 216; [WorkspaceTemplates.swift:87-101](../../../Sources/GraphiteUI/WorkspaceTemplates.swift#L87-L101) |
| 3 | Indexing | `isIndexing` 117, `indexingMessage` 116, `indexingTask` 199, `indexingRunIdentifier` 201, `pendingContentFileCount` 203, `isIndexScanRequestedDuringScan` 206, `hasCompletedIndexScan` 197, `indexVersion` 122, `propertyTypesVersion` 124 | `startIndexing` 516, `stopIndexing` 552, `rebuildIndex` 558, `refreshIndex` 580, `describeIndex` 591; `refreshIndexAfterFileChanges` [WorkspaceFileManagement.swift:313](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L313) |
| 4 | File list and sidebar state | `rootEntries` 18, `expandedFolders` 20 (persists in `didSet`), `directoryVersion` 118, `pickedSidebarFiles` 60, `recentFiles` 80 (persists in `didSet`) | `refreshDirectory` 495, `existingRecentFiles` 1287; `revealCurrentFile`, `collapseAllFolders`, `isDirectory` [WorkspaceFileManagement.swift:286-303](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L286-L303) |
| 5 | Search | `searchQuery` 105, `searchFocusRequest` 107, `searchResults` 108, `searchContinuation` 110, `isLoadingMoreSearchResults` 111 | `searchQueryProblem` 598, `search` 603, `loadMoreSearchResults` 622, `open(_:at:)` 640; `searchForTag`/`searchForProperty` [WorkspaceTagsAndProperties.swift:35-43](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L35-L43) |
| 6 | External changes | `externalChangeTask` 207, `pendingExternalChanges` 208, `firstPendingExternalChangeInstant` 1277 | `scheduleExternalRefresh` 1226, `externalRefreshDeadline` 1281, `checkOpenDocumentsForExternalChanges` 1358, `filesSavedOutsideEditors` 816 |
| 7 | Tabs and loaded documents | `layout` 40, `tabDocuments` 57, `selection` 92, `activeTabID` 97, `openTabCount` 99, `history` 104, `pdfPasswords` 78, `markdownEditorRetention` 65, `restorableSidebarPluginViews` 63 | `open` 428, `saveOpenDocuments` 487, `openBase` 805, `showBlock` 728, `noteOnOtherSide` 974, `openPDFSession` 1311, `resolvePDFConflict` 1391; 30 functions in WorkspaceTabs.swift; plugin views [CommunityPluginViews.swift:195-311](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L195-L311) |
| 8 | Links and new files | `embeddedBaseModelCache` 72 | `resolveLink` 652, `follow` 667, `createNote` 711/737, `createBase` 779, `createNotebook` 822, `baseEmbedContext` 793, `isNameUnique` 987, `linkText` 943, `pdfPageLink` 967, `insertLink` 959; `createCanvas` [WorkspaceCanvas.swift:22](../../../Sources/GraphiteUI/WorkspaceCanvas.swift#L22) |
| 9 | Attachments | `resolver` 209 | `importAttachment` 836, `saveAttachment` 858, `insertEmbed` 875, `insertionRange` 897/904, `saveUnderFreeName` 922, `pastedImageStem` 936, `embed` 980, `attachmentDirectoryDescription` 995; `addLassoPicture` [LassoTools.swift:77](../../../Sources/GraphiteUI/LassoTools.swift#L77) |
| 10 | Drawings | `drawingEditorRequest` 168, `noteTextWhenDrawingBegan` 1011, `drawingVersion` 120, `viewedImage` 172, `viewedImageNote` 170 | `beginNewDrawing` 1015, `beginEditingDrawing` 1026, `saveDrawing` 1041, `exportDrawingCopy` 1080; [WorkspaceImageDrawing.swift:20-125](../../../Sources/GraphiteUI/WorkspaceImageDrawing.swift#L20-L125) |
| 11 | Recording | `recording` 179, `recordingNotePath` 1097, `recordingFolderAccess` 1101, `showsRecordingPreview` 1105, `recordingRecoveryOffer` 158 | `startRecording` 1109, `recordingDirectory` 1139, `retryRecordingPublication` 1148, `freshRecordingDestination` 1156, `recordingTimestamp` 1174, `recordingDidFinish` 1180; [WorkspaceRecordingRecovery.swift:7-42](../../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L7-L42) |
| 12 | File management | `pendingMove` 31, `pendingDeletion` 33, `fileSheet` 35, `pathsBeingMoved` 38 | `followMoveInNavigation` 1201, `forgetInNavigation` 1216; 15 functions in [WorkspaceFileManagement.swift:46-316](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L46-L316) |
| 13 | Per-vault device memory | `documentPlaceStore` 69 | key builders 27, 87; places [WorkspacePlaces.swift:8-71](../../../Sources/GraphiteUI/WorkspacePlaces.swift#L8-L71); folds [WorkspaceFolds.swift:7-54](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L7-L54); `saveTabLayout`/`restoreTabLayout` [WorkspaceTabs.swift:419-443](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L419-L443) |
| 14 | File recovery | `fileRecovery` 74, `fileRecoveryRequest` 76 | [WorkspaceRecovery.swift:7-74](../../../Sources/GraphiteUI/WorkspaceRecovery.swift#L7-L74) |
| 15 | Conflict versions | `conflictedPaths` 161, `conflictVersionsRequest` 163, `conflictVersionStore` 165, `pendingConflictChecks` 166, `conflictCheckTask` 167 | [WorkspaceConflictVersions.swift:33-192](../../../Sources/GraphiteUI/WorkspaceConflictVersions.swift#L33-L192) |
| 16 | Vault appearance and theme | `vaultAppearance` 129, `noteTypography` 131, `noteTheme` 133, `themeRefreshTask` 134, `themeResolver` 135, `lastThemeInputs` 136, `pendingAppearanceSave` 139 | [WorkspaceAppearance.swift:12-129](../../../Sources/GraphiteUI/WorkspaceAppearance.swift#L12-L129), [WorkspaceTheme.swift:13-63](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L13-L63) |
| 17 | Bookmarks | `bookmarks` 144 | [WorkspaceBookmarks.swift:7-96](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L7-L96) |
| 18 | Graph and map | `graphCache` 146, `graphPositions` 148, `isGraphPresented` 150, `placedNotesCache` 152, `isMapPresented` 154 | [WorkspaceGraph.swift:7-34](../../../Sources/GraphiteUI/WorkspaceGraph.swift#L7-L34), [WorkspaceMap.swift:8-23](../../../Sources/GraphiteUI/WorkspaceMap.swift#L8-L23) |
| 19 | Read Aloud | `readAloud` 180, `calloutFolds` 182, `readAloudNavigator` 184 | `startReadingAloud` 1457 |
| 20 | Community plugins | `communityPlugins` 194 | plugin views (row 7) |
| 21 | Messages and presentation flags | `errorMessage` 112, `notice` 115, `isVaultManagerPresented` 156 | — (82 writers, see SRP-SHELL-03) |
| 22 | Device preferences | `preferences` 178 | — |

**Calls that cross responsibilities (the coupling a split must preserve).**
- **Loading a file into a tab touches 9 other responsibilities**: Read Aloud text tracking, folds, places, recovery watching, recent files, the vault library's last document, PDF release, conflict checks and editor retention ([WorkspaceTabs.swift:348-400](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L348-L400)).
- **A move or rename fans out to 8 kinds of state**: tabs, conflict marks, the layout, recent files, folds, places, bookmarks and recovery copies ([WorkspaceModel.swift:1201-1213](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1201-L1213)). Deletion fans out to 5 ([WorkspaceModel.swift:1216-1222](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1216-L1222)).
- **One external-change batch reaches 8 consumers**: appearance, theme, plugin styles, open documents, conflict checks, the directory, the drawing version and the index ([WorkspaceModel.swift:1247-1268](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1247-L1268)).
- **Closing tabs** remembers places, closes plugin views and drops retained editors ([WorkspaceTabs.swift:209-219](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L209-L219)).
- **Every `layout` change that alters the saved form** writes the layout, including plugin views ([WorkspaceModel.swift:50](../../../Sources/GraphiteUI/WorkspaceModel.swift#L50), [CommunityPluginViews.swift:256-268](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L256-L268)).
- **Applying appearance** notifies plugins, schedules a theme refresh and writes `preferences.vaultAccentHex` ([WorkspaceAppearance.swift:27-42](../../../Sources/GraphiteUI/WorkspaceAppearance.swift#L27-L42)).
- **Starting a recording** stops Read Aloud ([WorkspaceModel.swift:1114-1115](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1114-L1115)).
- **Every file-creating function calls `refreshIndex` and then `refreshDirectory` by hand.** This holds for `createNote`, `createBase`, `createNotebook`, `importAttachment` and `saveAttachment` ([WorkspaceModel.swift:720-721](../../../Sources/GraphiteUI/WorkspaceModel.swift#L720-L721), [787-788](../../../Sources/GraphiteUI/WorkspaceModel.swift#L787-L788), [830-831](../../../Sources/GraphiteUI/WorkspaceModel.swift#L830-L831), [849-850](../../../Sources/GraphiteUI/WorkspaceModel.swift#L849-L850), [867-868](../../../Sources/GraphiteUI/WorkspaceModel.swift#L867-L868)), and also for `createCanvas`, `openDailyNote`, `recover` and `restore`.

**Lifecycle and ordering rules it relies on.**
1. **During a vault switch, `layoutVaultIdentifier` is cleared before `layout` is replaced** ([WorkspaceModel.swift:311-312](../../../Sources/GraphiteUI/WorkspaceModel.swift#L311-L312)). The `didSet` at line 50 would otherwise save the empty layout over the vault being left. `restoreTabLayout` sets it back ([WorkspaceTabs.swift:441](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L441)).
2. **`expandedFolders` and `recentFiles` are replaced only after `currentVaultIdentifier` changes** ([WorkspaceModel.swift:316-317](../../../Sources/GraphiteUI/WorkspaceModel.swift#L316-L317), [329-336](../../../Sources/GraphiteUI/WorkspaceModel.swift#L329-L336)). Their `didSet` writes under the current identifier ([WorkspaceModel.swift:20-24](../../../Sources/GraphiteUI/WorkspaceModel.swift#L20-L24), [80-85](../../../Sources/GraphiteUI/WorkspaceModel.swift#L80-L85)).
3. **The open documents are saved twice during a switch.** Once after reading the new vault, where a failure keeps the old vault ([WorkspaceModel.swift:291](../../../Sources/GraphiteUI/WorkspaceModel.swift#L291)), and again until nothing is unsaved just before the sessions are dropped ([WorkspaceModel.swift:302](../../../Sources/GraphiteUI/WorkspaceModel.swift#L302)).
4. **Plugins of the old vault unload before anything closes** ([WorkspaceModel.swift:299](../../../Sources/GraphiteUI/WorkspaceModel.swift#L299)). They load after the tab layout is restored ([WorkspaceModel.swift:342-344](../../../Sources/GraphiteUI/WorkspaceModel.swift#L342-L344)).
5. **A pending font-size write belongs to the vault being left and is flushed before the switch** ([WorkspaceModel.swift:293](../../../Sources/GraphiteUI/WorkspaceModel.swift#L293)). It is also flushed before a reload, so it is not lost ([WorkspaceAppearance.swift:67](../../../Sources/GraphiteUI/WorkspaceAppearance.swift#L67)).
6. **`stopIndexing` replaces the run identifier**, so a cancelled scan reports nothing ([WorkspaceModel.swift:552-556](../../../Sources/GraphiteUI/WorkspaceModel.swift#L552-L556), checked at [529](../../../Sources/GraphiteUI/WorkspaceModel.swift#L529) and [541](../../../Sources/GraphiteUI/WorkspaceModel.swift#L541)).
7. **Async work re-checks that it still talks to the same vault before applying its result**: `self.index === index` ([WorkspaceModel.swift:567](../../../Sources/GraphiteUI/WorkspaceModel.swift#L567), [571](../../../Sources/GraphiteUI/WorkspaceModel.swift#L571), [586](../../../Sources/GraphiteUI/WorkspaceModel.swift#L586)), `store === refreshedStore` ([1245](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1245)), and `folderAccess?.root == root` ([WorkspaceConflictVersions.swift:59](../../../Sources/GraphiteUI/WorkspaceConflictVersions.swift#L59)).
8. **A document's place is remembered before its sessions are dropped** ([WorkspaceTabs.swift:211](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L211), [268](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L268), [388](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L388)).
9. **Saves outside the editors must be followed by `filesSavedOutsideEditors`**, or the open tab's next save conflicts ([WorkspaceModel.swift:812-820](../../../Sources/GraphiteUI/WorkspaceModel.swift#L812-L820)).
10. **`drawingVersion` must be increased after any write that previews show** ([WorkspaceModel.swift:1075](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1075), [1266-1267](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1266-L1267), [WorkspaceConflictVersions.swift:182](../../../Sources/GraphiteUI/WorkspaceConflictVersions.swift#L182)).

**Verdict.** This is the application-wide aggregate the rules forbid. The extensions organise the source, but every feature still shares one object, one `errorMessage`, and a hand-written vault-switch reset. The derived fields of rule 1 are already projected well (`selection`, `history`, `activeTabID`, `openTabCount`); the rest is not.

**Proposed split.** New types are owned by a thin `Workspace` composition object that holds no logic; views receive the types they use.

| New type | Members moved from `WorkspaceModel` |
| --- | --- |
| `OpenVault` (value: access, store, index, monitor, identifier) + `VaultSwitcher` | rows 1–2; `openVault` becomes "build a new `OpenVault`, then hand it to every `VaultScoped` model" |
| `VaultIndexing` | row 3 |
| `VaultFileList` | row 4 (minus persistence), `refreshDirectory` |
| `VaultSearch` | row 5 |
| `ExternalChangeCoordinator` | row 6, emitting typed change events to the models that subscribe |
| `TabWorkspace` + `DocumentOpener` registry (one opener per `DocumentKind`) | row 7 and `WorkspaceTabs.swift`; `TabDocument` keeps one `DocumentSession` value instead of three optionals |
| `NoteCreation` | row 8 creation functions; one `afterWrite(paths:)` hook that refreshes index and directory |
| `AttachmentPublisher` | row 9 |
| `DrawingWorkflow` | row 10 |
| `RecordingWorkflow` | row 11 |
| `FileManagement` | row 12 |
| `VaultDeviceMemory` (typed key registry for all per-vault keys) | row 13, the `didSet` persistence of rows 4 and 7 |
| `FileRecoveryModel`, `ConflictVersionTracker`, `VaultAppearanceModel`, `BookmarksModel`, `GraphAndMapCache` | rows 14–18 |
| `WorkspaceAlerts` (typed alerts queue) | row 21 |

### 3.2 `GraphiteRootView` (475 code lines in one declaration, [GraphiteRootView.swift:7-587](../../../Sources/GraphiteUI/GraphiteRootView.swift#L7-L587))

Stored state, counted by reading lines 8-39: 16 `@State`/`@AppStorage` properties, 3 environment values, and 1 static mutable set ([GraphiteRootView.swift:565](../../../Sources/GraphiteUI/GraphiteRootView.swift#L565)).

| Responsibility | State | Members |
| --- | --- | --- |
| Window layout | `columnVisibility` 20, `preferredCompactColumn` 23, `showsInspector` 18, `focusMode` 28, `isWindowTallerThanWide` 31, `isKeyboardShown` 27 | `sidebarVisibility` 506-518, `automaticHidesSidebar` 522, `showSidebar` 530, `showDocumentColumn` 538, `toggleFocusMode` 542, `onChange` handlers 82-93 |
| Palettes and sheets | `activePalette` 19, `showsSettings` 10, `opensVaultManagerAfterSettings` 16, `creation` 17, `showsTabSwitcher` 24 | `paletteOverlay` 400, `showTemplatePicker` 467, `windowActions` 434, 12 presentations in `body` 106-250 |
| Launch and deep links | `isVaultRestored` 14, `pendingLinks` 15, `isRestoringVault` 34 | `.task` 203-211, `.onOpenURL` 224-226, `documentArea` 419 |
| Scene lifecycle and saving | — | `.onChange(of: scenePhase)` 227-238, `save` 481, `saveBeforeLeavingScreen` 486, `BackgroundTaskAssertion` 592-606 |
| Toolbars | `usesFloatingPlayer` 12 | `detailToolbar` 298, `compactBottomBar` 371, `showsRecordingControl` 360, `focusedDocumentHasMoreMenu` 346 |
| Cross-feature arbitration | — | Read Aloud stops when recording starts 127-130; recording completion forwards to the model 248-250 |
| Drawing draft recovery | `draftIdentifiersOpenInThisProcess` (static) 565 | `reopenDrawingDraft` 569-585, `preserveDraft` closure 182-188 |
| Title rename | — | `titleBinding` 288-296 |
| Same file, other concepts | — | `PaperSizePreset` 611, `CustomPaperSize` 632, `CreateDocumentSheet` 642-743, `DocumentTitle` 749 |

**Ordering rules.**
- **Places are taken synchronously when the scene leaves `.active`, before the save task starts** ([GraphiteRootView.swift:228-231](../../../Sources/GraphiteUI/GraphiteRootView.swift#L228-L231)).
- **Links received before the vault has reopened are queued** and handled in arrival order afterwards ([GraphiteRootView.swift:203-211](../../../Sources/GraphiteUI/GraphiteRootView.swift#L203-L211)).
- **The template picker waits 250 ms** so that the command palette's close does not cancel it ([GraphiteRootView.swift:467-475](../../../Sources/GraphiteUI/GraphiteRootView.swift#L467-L475)).

**Verdict.** Mixed. The view is the right owner of window layout, but it also holds application lifecycle, the link queue and draft recovery.

**Split.**
- `WorkspaceWindowLayout`: an `@Observable` holding columns, inspector, focus mode and active palette, plus the existing pure visibility functions.
- `WorkspacePresentations`: a `ViewModifier` with all sheets and covers, like `FileManagementPresentation` already is.
- `SceneLifecycleSaver`: one owner of "save on leaving screen" for both the iPad scene phase and the Mac quit path.
- `DeepLinkInbox`: the queue and the restore gate.
- `DrawingDraftRecovery`: moved next to `DrawingEditorDraftStore`, with its process set owned by that store.
- `CreateDocumentSheet` and the paper presets move to their own file.

### 3.3 `VaultSidebar` (329 code lines, [VaultSidebar.swift:51-452](../../../Sources/GraphiteUI/VaultSidebar.swift#L51-L452))

The view has 16 properties, counted by reading lines 52-71: 4 inputs, 9 state or storage properties, and 3 environment values. Its responsibilities:
- **Panel picker with plugin views** ([VaultSidebar.swift:73-119](../../../Sources/GraphiteUI/VaultSidebar.swift#L73-L119), [202-218](../../../Sources/GraphiteUI/VaultSidebar.swift#L202-L218)).
- **Search** (field, 180 ms debounce, results, sort, suggestions) ([VaultSidebar.swift:161-173](../../../Sources/GraphiteUI/VaultSidebar.swift#L161-L173), [392-451](../../../Sources/GraphiteUI/VaultSidebar.swift#L392-L451)).
- **Creation menu** ([VaultSidebar.swift:251-261](../../../Sources/GraphiteUI/VaultSidebar.swift#L251-L261)).
- **Opening on selection**, which resigns the first responder ([VaultSidebar.swift:349-364](../../../Sources/GraphiteUI/VaultSidebar.swift#L349-L364)).
- **Picking files for plugins** ([VaultSidebar.swift:302-346](../../../Sources/GraphiteUI/VaultSidebar.swift#L302-L346)).
- **Drops onto the root** ([VaultSidebar.swift:320-327](../../../Sources/GraphiteUI/VaultSidebar.swift#L320-L327)).
- **Reveal-and-scroll polling** ([VaultSidebar.swift:124-134](../../../Sources/GraphiteUI/VaultSidebar.swift#L124-L134)).
- **Loading the Tags, Properties and Bookmarks lists**, keyed by a composed string ([VaultSidebar.swift:146-148](../../../Sources/GraphiteUI/VaultSidebar.swift#L146-L148)).

The same file holds 19 more types, among them rename, move and new-folder sheets and the file-sheet presentation.

**Verdict.** Mixed. The row types are carefully optimised (section 6), but the sidebar view itself is a hub.

**Split.**
- `SidebarPanelPicker`, keeping the panel enum's descriptor.
- `SidebarSearchModel` (query, debounce, paging) with `SidebarSearchResults`.
- `SidebarFileList`.
- A shared `CreationCatalogue` for every "New …" menu (OCP-SHELL-05).
- `FileSheets.swift` for the sheets.

### 3.4 `GraphitePreferences` (36 stored properties, [GraphitePreferences.swift:153-416](../../../Sources/GraphiteUI/GraphitePreferences.swift#L153-L416))

Counted by reading lines 207-355.

| Group | Properties | Count |
| --- | --- | ---: |
| Storage | `defaults` | 1 |
| Core plugin switches | `disabledCorePlugins` | 1 |
| Editor | `usesReadableLineLength`, `defaultNoteView`, `defaultEditingMode`, `usesSpellChecking`, `formatsCodeBlocks`, `showsInlineTitle` | 6 |
| Appearance | `appearanceMode`, `chosenAccentHex`, `vaultAccentHex` (not persisted; set by the workspace), `usesVaultTheme`, `legacyChosenTextSize` | 5 |
| Files, search, palette | `showsFileExtensions`, `searchSortOrder`, `recentCommandIdentifiers` | 3 |
| Recorder | `embedsRecordingsInNote`, `recordingCamera` | 2 |
| File recovery | `snapshotIntervalMinutes`, `snapshotHistoryDays` | 2 |
| Drawings and Pencil | `drawingFormat`, `drawingBackground`, `drawsOnPencilDoubleTap`, `drawingPaperPattern`, `drawingPaperAppearsInNotes`, `drawingPaperSpacing`, `drawingPaperLineColor`, `drawingPaperLineStrength`, `makesShapesOnHold`, `pencilToolbarStyle` | 10 |
| Notebook paper | `notebookPaperSpacing`, `notebookPaperColor`, `notebookLineColor`, `notebookLineStrength` | 4 |
| Palettes | `colorPalette`, `highlighterPalette` | 2 |

**Coupling.**
- **Four `nonisolated static` readers reread the same keys** for code that has no instance ([GraphitePreferences.swift:228-265](../../../Sources/GraphiteUI/GraphitePreferences.swift#L228-L265), [343-350](../../../Sources/GraphiteUI/GraphitePreferences.swift#L343-L350)).
- **Views read two keys directly through `@AppStorage`** ([WorkspacePanes.swift:167](../../../Sources/GraphiteUI/WorkspacePanes.swift#L167) reads `PencilToolbarStyle.preferenceKey`; [SettingsView.swift:470-472](../../../Sources/GraphiteUI/SettingsView.swift#L470-L472)).
- **Each key therefore has two or three readers.** `vaultAccentHex` is per-vault state stored in a per-device object.

**Verdict.** Weak on S: the object holds one kind of work (device preferences) but serves 9 feature areas, and it is the reason `SettingsView` pages take the whole object.

**Split.**
- One small `@Observable` per area: `EditorPreferences`, `AppearancePreferences`, `DrawingPreferences` (with notebook paper and Pencil), `RecorderPreferences`, `FileRecoveryPreferences`, `CorePluginSwitches`.
- All of them read and write through one typed `PreferenceKey<Value>` registry, which the static readers and `@AppStorage` users also use.
- `vaultAccentHex` moves to `VaultAppearanceModel`.

### 3.5 `FileTreeController` (about 300 code lines, [MacFileTree.swift:68-428](../../../Sources/GraphiteUI/MacFileTree.swift#L68-L428))

Six stored properties plus the `State` snapshot. It follows the workspace through a value snapshot compared for equality ([MacFileTree.swift:71-80](../../../Sources/GraphiteUI/MacFileTree.swift#L71-L80), [144-168](../../../Sources/GraphiteUI/MacFileTree.swift#L144-L168)). It reuses nodes by path ([MacFileTree.swift:171-184](../../../Sources/GraphiteUI/MacFileTree.swift#L171-L184)), lists folders in the background, and writes expansion back to `workspace.expandedFolders` ([MacFileTree.swift:349-361](../../../Sources/GraphiteUI/MacFileTree.swift#L349-L361)). The `isApplyingState` flag separates the controller's own changes from the person's ([MacFileTree.swift:91-93](../../../Sources/GraphiteUI/MacFileTree.swift#L91-L93)).

**Verdict.** Mostly strong. It needs from the workspace only:
- `store`, to list children;
- the snapshot fields;
- `open`, `move` and `checkConflictVersions`;
- `expandedFolders`;
- `errorMessage`;
- `preferences.displayName`.

This set is the natural narrow interface for both file trees.

## 4. Findings by principle

### S

#### SRP-SHELL-01 `WorkspaceModel` is one application-wide aggregate with 86 stored properties and about 15 responsibilities
- **Severity:** High
- **Evidence:**
  - Stored properties at [WorkspaceModel.swift:12-209](../../../Sources/GraphiteUI/WorkspaceModel.swift#L12-L209), [1011](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1011), [1097-1105](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1097-L1105) and [1277](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1277): 86, counted by reading.
  - 74 functions in the main file (grep `func \w+`), plus 24 extension blocks in 23 files (grep `extension WorkspaceModel`).
  - Responsibility map in section 3.1.
- **Why it matters:**
  - Every feature change edits or recompiles the same type: [WorkspaceModel.swift](../../../Sources/GraphiteUI/WorkspaceModel.swift) has 29 commits, the most in the area.
  - No feature can be tested without opening a real vault through the whole object. Its tests are integration tests on real folders and the process's standard defaults ([UiWorkspaceModelFixTests.swift:17-37](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L17-L37), [68-72](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L68-L72)).
  - Any view that reads one property is invalidated by Observation along a path that crosses unrelated features. That is why the projections at [WorkspaceModel.swift:40-52](../../../Sources/GraphiteUI/WorkspaceModel.swift#L40-L52) were needed.
- **Fix direction:** Split by the table in section 3.1 into vault-scoped models owned by a composition object with no logic. Each view takes the one or two models it reads.

#### SRP-SHELL-02 The vault switch resets per-vault state field by field; a new field must be remembered in `openVault`
- **Severity:** High
- **Evidence:**
  - [WorkspaceModel.swift:303-337](../../../Sources/GraphiteUI/WorkspaceModel.swift#L303-L337) assigns or clears 33 fields one by one (counted by reading). Examples: `layout`, `tabDocuments`, `pdfPasswords`, `graphCache`, `pendingMove`, `searchQuery`, `rootEntries`, `vaultSettings`, `fileRecovery`.
  - The same function calls 7 feature-specific resets: `resetConflictVersions`, `applyVaultAppearance`, `discardHiddenEditors`, `readAloud.clear`, `EmbeddedPDFSessions.shared.useVault`, `communityPlugins.vaultWillClose` and `vaultDidOpen`.
  - These per-vault fields are **not** reset there: `notice`, `fileRecoveryRequest`, `drawingEditorRequest`, `noteTextWhenDrawingBegan`, `lastThemeInputs`, `viewedImage`, `isGraphPresented`, `isMapPresented`, `recordingRecoveryOffer`.
  - Ordering constraints inside the function are documented only by comments ([WorkspaceModel.swift:310-317](../../../Sources/GraphiteUI/WorkspaceModel.swift#L310-L317)).
- **Why it matters:** Correctness depends on whoever adds a per-vault field also editing this 80-line function in the right position. The removal path is a second hand-written list with the same problem (OCP-SHELL-06), and it already misses one (BUG-SHELL-02).
- **Fix direction:** Group a vault's state in an `OpenVault` value and models that conform to a `VaultScoped` protocol (`vaultDidClose`, `vaultDidOpen(_:)`). The switcher replaces the value and walks the conformers, and the coordinator names no feature.

#### SRP-SHELL-03 Outcomes of 80 operations are reported through one shared `errorMessage: String?` slot
- **Severity:** Medium
- **Evidence:**
  - 82 assignments in the `Workspace*.swift` files (grep `errorMessage = `, 84 matches, of which 2 set `pdfSession.errorMessage` at [WorkspaceModel.swift:1377](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1377) and [1385](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1385)).
  - Views and other types write it too: [VaultSidebar.swift:703](../../../Sources/GraphiteUI/VaultSidebar.swift#L703), [VaultSidebarPanels.swift:135](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L135), [SettingsView.swift:936](../../../Sources/GraphiteUI/SettingsView.swift#L936), [MacFileTree.swift:240](../../../Sources/GraphiteUI/MacFileTree.swift#L240), [GraphiteRootView.swift:483](../../../Sources/GraphiteUI/GraphiteRootView.swift#L483), [VaultSwitcher.swift:61](../../../Sources/GraphiteUI/VaultSwitcher.swift#L61).
  - The alert must be attached twice because a sheet hides the root's ([SettingsView.swift:86-88](../../../Sources/GraphiteUI/SettingsView.swift#L86-L88), [GraphiteRootView.swift:202](../../../Sources/GraphiteUI/GraphiteRootView.swift#L202)).
  - Vault opening throws instead, for the same reason ([WorkspaceModel.swift:221-222](../../../Sources/GraphiteUI/WorkspaceModel.swift#L221-L222)).
- **Why it matters:**
  - Two failures close together overwrite each other. For example, a move problem and an indexing error ([WorkspaceModel.swift:539](../../../Sources/GraphiteUI/WorkspaceModel.swift#L539)) are both reported by setting this one field.
  - Callers cannot react to a typed outcome: `open` returns only `UUID?`, and `load` returns `Bool` plus a side write.
  - Tests assert on message text ([UiWorkspaceModelFixTests.swift:398-399](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L398-L399), [474-475](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L474-L475)).
- **Fix direction:**
  - Operations throw or return a typed outcome.
  - One `WorkspaceAlerts` queue holds typed `WorkspaceAlert` values, and one presenter turns them into words.
  - Sheets present from the same queue.

#### SRP-SHELL-04 `GraphiteRootView` mixes window layout, twelve presentations, the deep-link queue, scene-lifecycle saving and draft recovery
- **Severity:** Medium
- **Evidence:**
  - `body` runs from [GraphiteRootView.swift:62-252](../../../Sources/GraphiteUI/GraphiteRootView.swift#L62-L252) (172 code lines). It holds 12 presentations:
    - Settings (106), Vault Manager (114) and the tab switcher (119);
    - the Read Aloud reader (123) and document creation (131);
    - the graph (147/151) and the map (158/162);
    - file recovery (167), the image viewer (172/197) and the drawing editor (177);
    - the message alert (202) and the recording alert (239).
  - Saving on scene changes: [227-238](../../../Sources/GraphiteUI/GraphiteRootView.swift#L227-L238), [486-504](../../../Sources/GraphiteUI/GraphiteRootView.swift#L486-L504).
  - Draft recovery with a static set: [563-585](../../../Sources/GraphiteUI/GraphiteRootView.swift#L563-L585).
  - The create sheet lives in the same file: [642-743](../../../Sources/GraphiteUI/GraphiteRootView.swift#L642-L743).
- **Why it matters:**
  - The file has 28 commits, second only to `WorkspaceModel.swift`.
  - Saving on leaving the screen exists here for iPad and separately in `GraphiteApplicationDelegate` for the Mac, with different behaviour (BUG-SHELL-03).
  - The view cannot be built in a test without the full model.
- **Fix direction:** Apply the split in section 3.2. The view composes `WorkspaceWindowLayout`, `WorkspacePresentations` and `SceneLifecycleSaver`.

#### SRP-SHELL-05 Views read the disk while drawing, and two model functions enumerate folders on the main actor
- **Severity:** Medium
- **Evidence (7 sites, counted by reading):**
  - `EmptyTabView.recentFiles` checks files with `fileExists` in `body` ([WorkspacePanes.swift:660-662](../../../Sources/GraphiteUI/WorkspacePanes.swift#L660-L662), [687](../../../Sources/GraphiteUI/WorkspacePanes.swift#L687), via [WorkspaceModel.swift:1287-1296](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1287-L1296)).
  - `QuickSwitcher.items` does the same for up to 20 files ([QuickPalette.swift:246](../../../Sources/GraphiteUI/QuickPalette.swift#L246)).
  - Each file recovery row checks the vault ([FileRecoverySheet.swift:34](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L34) via [WorkspaceRecovery.swift:10-13](../../../Sources/GraphiteUI/WorkspaceRecovery.swift#L10-L13)).
  - Each bookmark row checks the vault ([VaultSidebarPanels.swift:419-422](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L419-L422)), and so does its context menu (370).
  - The daily-notes footer checks the template file ([SettingsView.swift:749](../../../Sources/GraphiteUI/SettingsView.swift#L749)).
  - `templateFiles()` enumerates the Templates folder synchronously on the main actor, from the palette's `.task` ([WorkspaceTemplates.swift:7-18](../../../Sources/GraphiteUI/WorkspaceTemplates.swift#L7-L18), [QuickPalette.swift:379-382](../../../Sources/GraphiteUI/QuickPalette.swift#L379-L382)).
  - `isDirectory`, a resource-value read, is called from views and menus ([WorkspaceFileManagement.swift:300-303](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L300-L303), [WorkspacePanes.swift:237](../../../Sources/GraphiteUI/WorkspacePanes.swift#L237), [VaultSidebar.swift:984](../../../Sources/GraphiteUI/VaultSidebar.swift#L984)).
- **Why it matters:**
  - Every redraw repeats the I/O. On a cloud-backed vault, a `fileExists` call can block on the file provider.
  - The editor-responsiveness priority in OBJECTIVE.md is put at risk by main-thread I/O in view updates.
- **Fix direction:**
  - "Recent files that exist", "is in vault" and the template list become model state, refreshed off the main actor when the directory version changes.
  - Views read values only.

#### SRP-SHELL-06 `GraphitePreferences` serves nine feature areas with 36 stored properties, and its file holds eight unrelated concepts
- **Severity:** Medium
- **Evidence:**
  - Section 3.4.
  - The same file declares `CorePlugin` with titles, summaries and icons ([GraphitePreferences.swift:10-88](../../../Sources/GraphiteUI/GraphitePreferences.swift#L10-L88)).
  - It also declares `NoteViewMode`, `EditingMode`, `DefaultNoteView`, `AppearanceMode`, `PaletteColor` ([91-148](../../../Sources/GraphiteUI/GraphitePreferences.swift#L91-L148)) and `NotebookPaperSpacing` ([450-457](../../../Sources/GraphiteUI/GraphitePreferences.swift#L450-L457)).
  - It adds UI titles to 6 Core enums ([418-498](../../../Sources/GraphiteUI/GraphitePreferences.swift#L418-L498)).
- **Why it matters:**
  - Adding a drawing option and an editor option edit the same initializer, `GraphitePreferences.init`, which is 41 code lines.
  - Every settings page takes the whole object.
  - `vaultAccentHex` is per-vault state in a per-device store, written by the workspace ([WorkspaceAppearance.swift:38](../../../Sources/GraphiteUI/WorkspaceAppearance.swift#L38)).
- **Fix direction:** Split per area over one typed key registry (section 3.4), with one concept per file.

### O

#### OCP-SHELL-01 A new document kind touches 13 UI files, and three `default:` branches hide it from the compiler
- **Severity:** High
- **Evidence:** I traced the most recent kind, canvas (grep `\.canvas\b|canvasSession|createCanvas|CanvasSession`, excluding the canvas feature's own files and unrelated `canvas` properties). It is wired into 13 UI files besides `DocumentKind` in Core:

  | File | Sites |
  | --- | --- |
  | [WorkspaceTabs.swift:15](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L15) | session field, plus 36, 41, 47, 344, 373-374, 393 |
  | [WorkspaceModel.swift:1364](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1364) | external-change check |
  | [WorkspacePanes.swift:520](../../../Sources/GraphiteUI/WorkspacePanes.swift#L520) | pane, plus 678-679 |
  | [WorkspaceFileManagement.swift:106](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L106) | move save list, plus 158 |
  | [GraphiteRootView.swift:139](../../../Sources/GraphiteUI/GraphiteRootView.swift#L139) | creation, plus 347 |
  | [VaultSidebar.swift:23](../../../Sources/GraphiteUI/VaultSidebar.swift#L23) | plus 31, 255, 789, 839 |
  | [QuickPalette.swift:314](../../../Sources/GraphiteUI/QuickPalette.swift#L314) | icon |
  | [WorkspaceCommands.swift:39-40](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L39-L40) | palette command |
  | [GraphiteCommands.swift:68-69](../../../Sources/GraphiteUI/GraphiteCommands.swift#L68-L69) | menu command |
  | [GraphitePreferences.swift:37](../../../Sources/GraphiteUI/GraphitePreferences.swift#L37) | `CorePlugin` title, plus 61, 85 |
  | [WorkspaceCanvas.swift](../../../Sources/GraphiteUI/WorkspaceCanvas.swift) | open and create |
  | [DocumentModeToggle.swift:178](../../../Sources/GraphiteUI/DocumentModeToggle.swift#L178) | mode toggle |
  | [CommunityPluginHost.swift:500](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L500) | plugin-facing switch |

  `default:` over `DocumentKind` appears at [WorkspaceTabs.swift:376](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L376), [WorkspacePanes.swift:553](../../../Sources/GraphiteUI/WorkspacePanes.swift#L553) and [ConflictVersionsSheet.swift:354](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L354).
- **Why it matters:**
  - A missed site compiles and fails at run time. For example, a kind not added to `WorkspaceFileManagement.move`'s list of sessions with unsaved edits ([WorkspaceFileManagement.swift:105-106](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L105-L106)) is moved without its edits being indexed first.
  - `TabDocument` grows one optional session per kind, and `hasUnsavedChanges`, `unload` and `save` must each be extended ([WorkspaceTabs.swift:35-48](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L35-L48)).
- **Fix direction:**
  - Add a `DocumentKindHandler` descriptor per kind with: open session, pane, icon, whether it is creatable, its core plugin, and its More menu.
  - Register the handlers in one table.
  - `TabDocument` holds one `DocumentSession` (a protocol with save, unsaved state and external-change check).
  - Switches over `DocumentKind` are exhaustive.

#### OCP-SHELL-02 27 commands are declared twice, in the palette and in the menu bar, and shortcut labels are typed in three places
- **Severity:** Medium
- **Evidence:**
  - I compared [GraphiteCommands.swift:61-177](../../../Sources/GraphiteUI/GraphiteCommands.swift#L61-L177) with [WorkspaceCommands.swift:24-252](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L24-L252). The duplicated commands:
    - New Note, New Notebook, New Base, New Canvas, New Tab;
    - Quick Switcher, Search, Settings, Insert Template;
    - Close Tab, Reopen Closed Tab, Back, Forward, Next Tab, Previous Tab;
    - Toggle Reading, Toggle Source;
    - Toggle the left sidebar, Toggle the right sidebar;
    - Graph, Map, Split Right, Close Side, Focus Other Side;
    - the three daily-note commands.
  - Shortcut labels are written as text in the palette (`shortcut: "⌘N"`, [WorkspaceCommands.swift:28](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L28)). They are also written as text in the empty tab ([WorkspacePanes.swift:673](../../../Sources/GraphiteUI/WorkspacePanes.swift#L673), [681](../../../Sources/GraphiteUI/WorkspacePanes.swift#L681), [683](../../../Sources/GraphiteUI/WorkspacePanes.swift#L683)) and in a help tag ([WorkspacePanes.swift:255](../../../Sources/GraphiteUI/WorkspacePanes.swift#L255)).
  - Separately, they are bound as `.keyboardShortcut` ([GraphiteCommands.swift:63](../../../Sources/GraphiteUI/GraphiteCommands.swift#L63)).
- **Why it matters:**
  - A new command, or a changed shortcut, has to be made in up to four places.
  - Enablement rules are written twice and can drift. For example, the palette offers `next-tab` only when there is more than one tab ([WorkspaceCommands.swift:177](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L177)), while the menu disables it below two ([GraphiteCommands.swift:152](../../../Sources/GraphiteUI/GraphiteCommands.swift#L152)).
- **Fix direction:**
  - Define one `WorkspaceCommand` catalogue: identifier, title, menu placement, `KeyboardShortcut`, availability and action.
  - The palette, the menu bar and the shortcut hints all render it.
  - Labels come from the `KeyboardShortcut` value.

#### OCP-SHELL-03 A new sidebar panel touches 7 branch sites in 4 files, and the list falls back to the file tree silently
- **Severity:** Medium
- **Evidence:**
  - `SidebarPanel` has three switches: `title`, `systemImage` and `plugin` ([VaultSidebarPanels.swift:11-37](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L11-L37)).
  - `panelMenu` switches on it ([VaultSidebar.swift:228-249](../../../Sources/GraphiteUI/VaultSidebar.swift#L228-L249)).
  - `listContent` is an `if/else` chain whose last branch is the file tree ([VaultSidebar.swift:366-383](../../../Sources/GraphiteUI/VaultSidebar.swift#L366-L383)).
  - `VaultOverviewModel.load` switches on it ([VaultSidebarPanels.swift:122-133](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L122-L133)).
  - Commands that show a panel write its raw value into defaults ([WorkspaceCommands.swift:89](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L89)).
  - A plugin-provided panel adds three `CorePlugin` switch cases ([GraphitePreferences.swift:17-86](../../../Sources/GraphiteUI/GraphitePreferences.swift#L17-L86)).
- **Why it matters:** A panel added to the enum but not to `listContent` compiles and shows the file tree under its own icon.
- **Fix direction:**
  - Give each panel a descriptor that holds its title, icon, plugin, menu, list view and loader.
  - `listContent` switches exhaustively on the panel.

#### OCP-SHELL-04 A configurable plugin's settings page needs a list entry and a switch case; a missed case shows Core Plugins silently
- **Severity:** Low
- **Evidence:**
  - `configurablePlugins` list: [SettingsView.swift:22](../../../Sources/GraphiteUI/SettingsView.swift#L22).
  - Page switch with a catch-all `case .plugin:` that shows the Core Plugins page: [SettingsView.swift:110-116](../../../Sources/GraphiteUI/SettingsView.swift#L110-L116).
- **Why it matters:** The sidebar offers the page, and selecting it shows the wrong page without a compiler error.
- **Fix direction:**
  - `CorePlugin` gets an optional settings-page descriptor.
  - The list is derived from it, and the catch-all goes away.

#### OCP-SHELL-05 What can be created is listed seven times, each copy repeating the plugin gating
- **Severity:** Medium
- **Evidence:**
  - `CreationKind` with two switches: [VaultSidebar.swift:15-34](../../../Sources/GraphiteUI/VaultSidebar.swift#L15-L34).
  - Dispatch: [GraphiteRootView.swift:135-140](../../../Sources/GraphiteUI/GraphiteRootView.swift#L135-L140).
  - Sidebar New menu: [VaultSidebar.swift:251-258](../../../Sources/GraphiteUI/VaultSidebar.swift#L251-L258).
  - Folder menu: [VaultSidebar.swift:786-789](../../../Sources/GraphiteUI/VaultSidebar.swift#L786-L789).
  - Empty tab: [WorkspacePanes.swift:673-680](../../../Sources/GraphiteUI/WorkspacePanes.swift#L673-L680).
  - Palette: [WorkspaceCommands.swift:28-41](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L28-L41).
  - Menu bar: [GraphiteCommands.swift:62-70](../../../Sources/GraphiteUI/GraphiteCommands.swift#L62-L70).
  - `isEnabled(.bases)` and `isEnabled(.canvas)` gates are repeated in 5 of these lists (counted by reading).
- **Why it matters:** The lists already differ:
  - The New menu offers Daily Note, the folder menu does not.
  - The menu-bar New menu has no New Folder.
  - Icons differ between lists for the same kind: "doc.text" in the sidebar, "square.and.pencil" in the palette.
- **Fix direction:**
  - One `CreationCatalogue` holds each kind's title, icon, the plugin it requires and its create action.
  - Each menu filters this catalogue.

#### OCP-SHELL-06 "Forget a removed vault" names its per-vault state by hand, so new per-vault state is not forgotten
- **Severity:** Medium
- **Evidence:**
  - The cleanup is in [WorkspaceModel.swift:244-258](../../../Sources/GraphiteUI/WorkspaceModel.swift#L244-L258): recovery copies, the index, plugin consent, three key names, and the place store.
  - It cannot list the folds key, which is `private` in another file ([WorkspaceFolds.swift:7-9](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L7-L9)).
  - Drawing drafts carry a vault identifier ([GraphiteRootView.swift:185](../../../Sources/GraphiteUI/GraphiteRootView.swift#L185)), but the draft store has no per-vault removal: its public methods are `preserve`, `removeDraft` and `drafts` ([DrawingEditorDraftStore.swift:84-115](../../../Sources/GraphiteUI/DrawingEditorDraftStore.swift#L84-L115)).
- **Why it matters:** BUG-SHELL-02 is the result. Each new per-vault preference repeats the risk.
- **Fix direction:**
  - Per-vault device state registers with `VaultDeviceMemory` as a conformance (`forgetVault(_:)`).
  - Removal walks every registered conformer.
  - Keys are declared once in a typed registry.

#### OCP-SHELL-07 Bookmark kinds are compared as strings in 9 places
- **Severity:** Low
- **Evidence:**
  - `bookmark.type == "group"`, `"file"`, `"folder"`, `"search"` and `"url"` at [VaultSidebarPanels.swift:352](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L352), [370](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L370), [379](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L379), [390-403](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L390-L403), [420](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L420) and [425-435](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L425-L435).
  - The same in [WorkspaceBookmarks.swift:62-77](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L62-L77).
  - Three of these sites end in `default:`.
- **Why it matters:** A typo compiles. The vocabulary belongs to Obsidian's file format and should be mapped once.
- **Fix direction:**
  - Map `Bookmark.type` once, at the Core boundary, to an enum with an `unknown(raw)` case.
  - Views switch on that enum exhaustively.

### L

#### LSP-SHELL-01 Two implementations of "read this note aloud" disagree about folded text
- **Severity:** Medium
- **Evidence:**
  - The queue path passes folded headings and collapsed callouts as hidden ranges ([WorkspaceModel.swift:1459-1462](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1459-L1462)), and live edits do the same ([WorkspaceTabs.swift:350-355](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L350-L355)).
  - The `graphite://read` link path calls `readMarkdown(session.text, path:)` with no hidden ranges ([WorkspaceDeepLinks.swift:46](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L46)).
- **Why it matters:**
  - The same note is read differently depending on how reading started.
  - The link path also reads whichever note is focused rather than the linked one (BUG-SHELL-01).
- **Fix direction:**
  - Make one `readNoteAloud(at:resumeLocation:)` the only entry point.
  - It opens the note, checks that the session is the requested path, and computes the hidden ranges.

#### LSP-SHELL-02 Failed reads are shown as empty results
- **Severity:** Medium
- **Evidence (5 sites, counted by reading):**
  - File recovery: notes `(try? …) ?? []` ([FileRecoverySheet.swift:60](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L60)), snapshots ([FileRecoverySheet.swift:101](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L101)), snapshot text ([FileRecoverySheet.swift:145](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L145)).
  - Quick switcher: `try?` turns an index error into "No files match." ([QuickPalette.swift:234-238](../../../Sources/GraphiteUI/QuickPalette.swift#L234-L238)).
  - `resolveLink`: an index error counts as "no match" ([WorkspaceModel.swift:661](../../../Sources/GraphiteUI/WorkspaceModel.swift#L661)). `follow` then resolves again with `try` ([WorkspaceModel.swift:698](../../../Sources/GraphiteUI/WorkspaceModel.swift#L698)), so it reports the error, but `beginDrawingAtCursor` does not resolve again: on an index error it starts a new drawing ([WorkspaceImageDrawing.swift:49-52](../../../Sources/GraphiteUI/WorkspaceImageDrawing.swift#L49-L52)).
- **Why it matters:** The person is told there is nothing when something failed. For File Recovery this hides the copies they came to recover (BUG-SHELL-05).
- **Fix direction:**
  - Reads return `Result` or throw.
  - Views show a failure state distinct from the empty state.

#### LSP-SHELL-03 Platform variants of one function behave differently
- **Severity:** Low
- **Evidence:**
  - `SearchMatch.highlightedExcerpt(accent:)` highlights matches on iPad and iPhone, but returns plain text on the Mac ([VaultSidebar.swift:1153-1168](../../../Sources/GraphiteUI/VaultSidebar.swift#L1153-L1168)).
  - Copying to the pasteboard has two implementations with different conditional-compilation branches: `#else` in [WorkspacePanes.swift:592-600](../../../Sources/GraphiteUI/WorkspacePanes.swift#L592-L600), `#elseif canImport(AppKit)` in [VaultSidebar.swift:811-818](../../../Sources/GraphiteUI/VaultSidebar.swift#L811-L818).
- **Why it matters:** Search results and backlinks on the Mac show no highlights, and nothing records this as a known limitation.
- **Fix direction:**
  - Build the highlight with SwiftUI `AttributedString` attributes, which work on both platforms.
  - Delete `VaultEntryMenu.copyToPasteboard` in favour of `Pasteboard.copy`.

#### LSP-SHELL-04 Equality that ignores content is used deliberately in four types
- **Severity:** Low
- **Evidence:**
  - `TemplatePickerAction.==` and `DocumentRenameAction.==` always return true ([QuickPalette.swift:419](../../../Sources/GraphiteUI/QuickPalette.swift#L419), [434](../../../Sources/GraphiteUI/QuickPalette.swift#L434)).
  - `FileTreeRows.==` compares only workspace identity ([VaultSidebar.swift:593-595](../../../Sources/GraphiteUI/VaultSidebar.swift#L593-L595)).
  - `VaultEntryRow.==` ignores its closure ([VaultSidebar.swift:643-645](../../../Sources/GraphiteUI/VaultSidebar.swift#L643-L645)).
- **Why it matters:**
  - Each is documented and measured, and they prevent full-tree redraws (section 6).
  - The risk is a later change that makes the closure capture per-row state, which these `==` would then hide.
- **Fix direction:**
  - Keep them.
  - State the invariant "the closure captures only the stable binding" next to each one, and pin it with the redraw tests that already exist ([UiRedrawAvoidanceTests.swift](../../../Tests/GraphiteUITests/UiRedrawAvoidanceTests.swift)).

### I

#### ISP-SHELL-01 51 view declarations in scope take the whole `WorkspaceModel` to use one to seven members
- **Severity:** High
- **Evidence:**
  - grep `(var|let) workspace: WorkspaceModel` finds 70 declarations in 23 UI files, 51 of them in this area's files (VaultSidebar 11, SettingsView 9, WorkspacePanes 5, VaultSidebarPanels 5, others).
  - Members actually used, counted by reading:

    | View | Members used |
    | --- | --- |
    | `VaultItemDragPreview` | 1: `preferences.displayName` ([VaultSidebar.swift:822-829](../../../Sources/GraphiteUI/VaultSidebar.swift#L822-L829)) |
    | `SearchResultRow` | 2: `preferences.displayName`, `open(_:at:)` ([VaultSidebar.swift:512-554](../../../Sources/GraphiteUI/VaultSidebar.swift#L512-L554)) |
    | `ConflictVersionsBanner` | 2: `conflictedPaths`, `conflictVersionsRequest` ([ConflictVersionsSheet.swift:461-480](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L461-L480)) |
    | `TabSwitcher` | 7: `layout`, `openNewTab`, `activateTab`, `closeTab`, `closeOtherTabs`, `togglePin`, `preferences` ([TabSwitcher.swift:7-105](../../../Sources/GraphiteUI/TabSwitcher.swift#L7-L105)) |
- **Why it matters:**
  - No view can be previewed or tested without a full workspace.
  - Every view can mutate any workspace state. For example, the sidebar writes `searchResults` ([VaultSidebar.swift:171](../../../Sources/GraphiteUI/VaultSidebar.swift#L171)) and the panes write `layout.splitFraction` ([WorkspacePanes.swift:76](../../../Sources/GraphiteUI/WorkspacePanes.swift#L76), [80](../../../Sources/GraphiteUI/WorkspacePanes.swift#L80)).
  - Observation dependencies are hard to reason about. The redraw fixes in section 6 exist because of this.
- **Fix direction:**
  - Views take the split-out models (section 3.1), or value inputs plus intent closures.
  - Example: `TabSwitcher(tabs: TabWorkspace)`; `SearchResultRow(result:, displayName:, open:)`.

#### ISP-SHELL-02 `CommunityPluginHost` and `WorkspaceModel` reference each other; the host reads about 23 workspace members
- **Severity:** Medium
- **Evidence:**
  - Back-reference: `weak var workspace: WorkspaceModel?` ([CommunityPluginHost.swift:258](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L258)), set by `vaultDidOpen(self)` ([WorkspaceModel.swift:344](../../../Sources/GraphiteUI/WorkspaceModel.swift#L344)).
  - grep `workspace\??\.[a-zA-Z]+` over `CommunityPlugin*.swift` shows the members used: `store`, `errorMessage`, `folderAccess`, `currentVaultIdentifier`, `title`, `recentFiles`, `dailyNoteSettings`, `templateSettings`, `preferences`, `vaultSettings`, `markdownSession`, `selection`, `openMarkdownSession`, `open`, `follow`, `move`, `pendingMove`, `pluginViewsDidChange`, `openPluginViewInTab`, `openPluginViewBeside`, `restorePluginViews`, `vaultAppearance`, `updateVaultAppearance`, `scheduleThemeRefresh`.
  - In the other direction, the workspace calls host methods from the main file at [299](../../../Sources/GraphiteUI/WorkspaceModel.swift#L299), [344](../../../Sources/GraphiteUI/WorkspaceModel.swift#L344), [434-443](../../../Sources/GraphiteUI/WorkspaceModel.swift#L434-L443) and [1249](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1249), and from [WorkspaceTabs.swift:214](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L214).
- **Why it matters:** The plugin runtime, which OBJECTIVE.md wants isolated from user content and the main thread, can reach every workspace capability, including `move`. Neither type can be tested without the other.
- **Fix direction:**
  - Give the host a `PluginWorkspaceAccess` capability set: active document, open file, follow link, rename file, read settings, report error.
  - The workspace implements it, or the split models do.
  - Plugin-view tab placement moves to `TabWorkspace`, which the host calls through this capability set.

#### ISP-SHELL-03 Core workspace state is publicly settable, and tests and views assign it directly
- **Severity:** Medium
- **Evidence:**
  - `var folderAccess`, `var store`, `var index`, `var vaultSettings`, `var layout` and `var tabDocuments` are writable from outside the type ([WorkspaceModel.swift:12-57](../../../Sources/GraphiteUI/WorkspaceModel.swift#L12-L57), [125](../../../Sources/GraphiteUI/WorkspaceModel.swift#L125)).
  - Tests assign them: [UiWorkspaceModelFixTests.swift:83](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L83) and [UiRootSettingsTests.swift:224-225](../../../Tests/GraphiteUITests/UiRootSettingsTests.swift#L224-L225).
  - `hasCompletedIndexScan` is documented as set by tests that fill the index themselves ([WorkspaceModel.swift:195-197](../../../Sources/GraphiteUI/WorkspaceModel.swift#L195-L197)).
- **Why it matters:**
  - A test can build states production never reaches, such as a `store` with no `folderAccess` or `monitor`.
  - Any view can replace the vault.
- **Fix direction:**
  - `private(set)` on vault state.
  - Tests build a workspace through the same initializer as production, with injected adapters (DIP-SHELL-01).

#### ISP-SHELL-04 `WindowActions` carries 10 closures to every command consumer
- **Severity:** Low
- **Evidence:** [WorkspaceCommands.swift:5-19](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L5-L19). `WorkspaceMenuActions` adds the whole workspace on top ([GraphiteCommands.swift:6-11](../../../Sources/GraphiteUI/GraphiteCommands.swift#L6-L11)).
- **Why it matters:**
  - It is above the seven-member guideline.
  - It exists only because the two command registries need the same window intents (OCP-SHELL-02).
- **Fix direction:** Once one command catalogue exists, it takes `WorkspaceWindowLayout`, which owns these intents.

### D

#### DIP-SHELL-01 `WorkspaceModel` constructs its own I/O collaborators, so no test can isolate it
- **Severity:** High
- **Evidence:**
  - Fields constructed in place:
    - `VaultLibrary()` with `.standard` defaults ([WorkspaceModel.swift:15](../../../Sources/GraphiteUI/WorkspaceModel.swift#L15));
    - `GraphitePreferences()` ([178](../../../Sources/GraphiteUI/WorkspaceModel.swift#L178));
    - `RecordingController()` ([179](../../../Sources/GraphiteUI/WorkspaceModel.swift#L179));
    - `ReadAloudVoices.makeController()` ([180](../../../Sources/GraphiteUI/WorkspaceModel.swift#L180));
    - `CommunityPluginHost()` ([194](../../../Sources/GraphiteUI/WorkspaceModel.swift#L194));
    - `FileProviderConflictVersions()` ([165](../../../Sources/GraphiteUI/WorkspaceModel.swift#L165));
    - `DocumentPlaceStore.shared` ([69](../../../Sources/GraphiteUI/WorkspaceModel.swift#L69)).
  - `openVault` builds `VaultMonitor`, `VaultStore` and `VaultIndex` and calls `EmbeddedPDFSessions.shared` ([WorkspaceModel.swift:273-309](../../../Sources/GraphiteUI/WorkspaceModel.swift#L273-L309)).
  - There is no initializer: every test calls `WorkspaceModel()` (grep `WorkspaceModel\(` in Tests, 20+ matches).
- **Why it matters:**
  - Tests read and write the developer's or CI's real `UserDefaults.standard`, and must save and restore every `Graphite*` key ([UiWorkspaceModelFixTests.swift:17-37](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L17-L37)). Keys without that prefix, such as `sidebarPanel`, leak between tests.
  - Every workspace test creates a recorder and a plugin host.
  - Two test processes running at once share one store.
- **Fix direction:**
  - Add an initializer that takes `WorkspaceDependencies`: defaults, vault library, preferences, place store, conflict store, recorder, plugin host, and a vault opener that builds store, index and monitor.
  - The app's composition root passes the real ones.
  - Tests pass a private defaults suite and test doubles that keep production semantics.

#### DIP-SHELL-02 Per-vault device state is written to `UserDefaults.standard` under five concatenated key families in five files
- **Severity:** Medium
- **Evidence:**
  - The key families:

    | Key | Declared at |
    | --- | --- |
    | `"GraphiteExpandedFolders." + uuid` | [WorkspaceModel.swift:28](../../../Sources/GraphiteUI/WorkspaceModel.swift#L28) |
    | `"GraphiteRecentFiles." + uuid` | [WorkspaceModel.swift:88](../../../Sources/GraphiteUI/WorkspaceModel.swift#L88) |
    | `"GraphiteTabLayout." + uuid` | [WorkspaceTabs.swift:86](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L86) |
    | `"GraphiteDocumentPlaces." + uuid` | [WorkspacePlaces.swift:9](../../../Sources/GraphiteUI/WorkspacePlaces.swift#L9) |
    | `"GraphiteFolds." + uuid` | [WorkspaceFolds.swift:8](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L8) |

  - Direct `UserDefaults.standard` reads and writes:
    - [WorkspaceModel.swift:23](../../../Sources/GraphiteUI/WorkspaceModel.swift#L23), [83](../../../Sources/GraphiteUI/WorkspaceModel.swift#L83), [255](../../../Sources/GraphiteUI/WorkspaceModel.swift#L255), [332](../../../Sources/GraphiteUI/WorkspaceModel.swift#L332), [334](../../../Sources/GraphiteUI/WorkspaceModel.swift#L334);
    - [WorkspaceFolds.swift:14](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L14), [18](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L18);
    - [WorkspaceTabs.swift:421](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L421), [432](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L432).
  - Places go through an injectable store; the other four families do not.
  - The folds dictionary is read and rewritten whole on every fold change ([WorkspaceFolds.swift:26-31](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L26-L31)).
- **Why it matters:**
  - No single list of per-vault keys exists (BUG-SHELL-02).
  - The formats are not versioned.
  - Tests cannot isolate them.
- **Fix direction:** Create `VaultDeviceMemory`, which holds:
  - one `PerVaultKey<Value: Codable>` registry, with the five existing key strings kept byte for byte;
  - an injected defaults store;
  - an in-memory cache, as `DocumentPlaceStore` has;
  - `forgetVault`, which removes every registered key.

#### DIP-SHELL-03 Model code and command code write view-owned storage keys; two keys are typed as string literals in several files
- **Severity:** Medium
- **Evidence:**
  - `SidebarPanelSettingKey.panel` is written from the model at [WorkspaceFileManagement.swift:288](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L288) and [WorkspaceBookmarks.swift:83](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L83), and from commands at [WorkspaceCommands.swift:89](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L89). The view reads it through `@AppStorage` ([VaultSidebar.swift:67](../../../Sources/GraphiteUI/VaultSidebar.swift#L67)).
  - The literal `"GraphiteInspectorPanel"` appears three times: written at [WorkspaceCommands.swift:71](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L71) and [82](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L82), read at [MarkdownPane.swift:891](../../../Sources/GraphiteUI/MarkdownPane.swift#L891).
  - The literal `"GraphiteReadAloudFloatingPlayer"` appears twice ([GraphiteRootView.swift:12](../../../Sources/GraphiteUI/GraphiteRootView.swift#L12), [SettingsView.swift:582](../../../Sources/GraphiteUI/SettingsView.swift#L582)).
- **Why it matters:**
  - "Which panel is shown" has three writers and no owner.
  - A typo in one literal splits the setting in two, and nothing catches it.
- **Fix direction:**
  - The sidebar and the inspector each own a small state model with an intent, `show(panel:)`.
  - Their persistence keys move into the typed registry.

#### DIP-SHELL-04 Static mutable state and singletons in shell code
- **Severity:** Medium
- **Evidence:**
  - Three mutable statics:
    - `GraphiteRootView.draftIdentifiersOpenInThisProcess` ([GraphiteRootView.swift:565](../../../Sources/GraphiteUI/GraphiteRootView.swift#L565));
    - `GraphitePreferences.accentColorsByHex`, which is unbounded and gains one entry per distinct hex the custom colour picker passes through ([GraphitePreferences.swift:308-315](../../../Sources/GraphiteUI/GraphitePreferences.swift#L308-L315), fed by [SettingsView.swift:263-265](../../../Sources/GraphiteUI/SettingsView.swift#L263-L265));
    - `GraphiteApplicationDelegate.workspaceToSave` ([GraphiteMacScenes.swift:46](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L46)).
  - 16 `.shared` uses in scope (reconnaissance count confirmed by reading):
    - `DrawingEditorDraftStore.shared` 4 ([GraphiteRootView.swift:185](../../../Sources/GraphiteUI/GraphiteRootView.swift#L185), [189](../../../Sources/GraphiteUI/GraphiteRootView.swift#L189), [570](../../../Sources/GraphiteUI/GraphiteRootView.swift#L570), [583](../../../Sources/GraphiteUI/GraphiteRootView.swift#L583));
    - `UIApplication.shared` 10;
    - `DocumentPlaceStore.shared` 1;
    - `EmbeddedPDFSessions.shared` 1.
- **Why it matters:**
  - The draft set and the delegate's workspace are process-global, so two root views in one test process interfere.
  - The colour cache grows for the life of the process.
- **Fix direction:**
  - The draft store owns the "open in this process" set.
  - The Mac composition root passes the workspace to the delegate.
  - The accent cache keeps the last few hex values, with a named bound.

#### DIP-SHELL-05 Logic reads the wall clock directly
- **Severity:** Low
- **Evidence:**
  - `Date()` at [WorkspacePlaces.swift:32](../../../Sources/GraphiteUI/WorkspacePlaces.swift#L32).
  - `.now` at [WorkspaceModel.swift:1049](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1049) and [1125](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1125), and in [VaultLibrary.swift:39](../../../Sources/GraphiteUI/VaultLibrary.swift#L39).
  - `ContinuousClock.now` at [WorkspaceModel.swift:1228](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1228) and [WorkspaceTabs.swift:33](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L33), [260](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L260).
  - `pastedImageStem` and `recordingTimestamp` already take the date as a parameter ([WorkspaceModel.swift:936](../../../Sources/GraphiteUI/WorkspaceModel.swift#L936), [1174](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1174)). That is the right pattern, and the tests use it ([UiWorkspaceModelFixTests.swift:480-488](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L480-L488)).
- **Why it matters:** Place ordering, PDF-release order and the external-refresh debounce cannot be tested deterministically through the model.
- **Fix direction:** One injected clock in the workspace dependencies. The pure functions keep their date parameters.

### Clean code

#### CC-SHELL-01 29 functions exceed 40 code lines; the root view's `body` is 172
- **Severity:** Medium
- **Evidence:** The reconnaissance list is in section 8; I confirmed the largest by reading.
  - [GraphiteRootView.swift:62-252](../../../Sources/GraphiteUI/GraphiteRootView.swift#L62-L252): 172 lines.
  - `WorkspaceCommandList.commands` [WorkspaceCommands.swift:24-143](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L24-L143): 120 lines.
  - `DrawingsSettingsPage.body` [SettingsView.swift:474-575](../../../Sources/GraphiteUI/SettingsView.swift#L474-L575): 102 lines.
  - `VaultSidebar.body` [VaultSidebar.swift:121-223](../../../Sources/GraphiteUI/VaultSidebar.swift#L121-L223): 84 lines.
  - `WorkspaceModel.load` [WorkspaceTabs.swift:329-415](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L329-L415): 77 lines.
  - `WorkspaceModel.openVault` [WorkspaceModel.swift:267-346](../../../Sources/GraphiteUI/WorkspaceModel.swift#L267-L346): 62 lines.
- **Why it matters:**
  - `load` mixes four jobs in one function: choosing a session by kind, saving, applying the swap, and updating six follow-up records.
  - `openVault` interleaves I/O with the reset of 33 fields.
  - Both are the riskiest code in the area to change.
- **Fix direction:**
  - `load` becomes three steps:
    1. `DocumentOpener.open(kind)`, which returns a session value;
    2. `TabWorkspace.swap(tab:session:)`;
    3. one `documentDidOpen` notification that the interested models observe.
  - `openVault` becomes "prepare `OpenVault`" followed by "install `OpenVault`" (SRP-SHELL-02).

#### CC-SHELL-02 Sleeps act as ordering or polling in five places
- **Severity:** Medium
- **Evidence:**
  - The template picker sleeps 250 ms to let the palette close ([GraphiteRootView.swift:467-475](../../../Sources/GraphiteUI/GraphiteRootView.swift#L467-L475)).
  - A deep link polls the index every 250 ms, up to 40 times, about 10 s in all ([WorkspaceDeepLinks.swift:80-86](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L80-L86)).
  - "Reveal current file" scrolls 10 times, once every 100 ms ([VaultSidebar.swift:124-134](../../../Sources/GraphiteUI/VaultSidebar.swift#L124-L134)).
  - The rename sheet waits 350 ms before selecting the name ([VaultSidebar.swift:1018-1024](../../../Sources/GraphiteUI/VaultSidebar.swift#L1018-L1024)).
  - The Mac file tree uses `DispatchQueue.main.async` to clear its binding ([MacFileTree.swift:42-45](../../../Sources/GraphiteUI/MacFileTree.swift#L42-L45)).
- **Why it matters:**
  - Each wait is a guess about another component's timing. On a slow iPad, for example, the folder rows may take more than 1 s to list, and the reveal then stops scrolling.
  - The deep-link poll keeps a task alive for 10 s with no owner that cancels it.
- **Fix direction:**
  - Await the event itself:
    - the index's scan-completion stream for the deep link;
    - the row's appearance (`onAppear` of the target row, or `revealPendingFile` as the Mac tree already does, [MacFileTree.swift:283-294](../../../Sources/GraphiteUI/MacFileTree.swift#L283-L294));
    - the palette's dismissal transaction.

#### CC-SHELL-03 "Latest answer wins" is implemented five different ways
- **Severity:** Low
- **Evidence:**
  - Indexing uses a run identifier ([WorkspaceModel.swift:523-529](../../../Sources/GraphiteUI/WorkspaceModel.swift#L523-L529)).
  - Tab loading uses a request identifier ([WorkspaceTabs.swift:336-339](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L336-L339)).
  - Search compares the query and sort it started with ([WorkspaceModel.swift:613](../../../Sources/GraphiteUI/WorkspaceModel.swift#L613), [629](../../../Sources/GraphiteUI/WorkspaceModel.swift#L629)).
  - The quick switcher stores the query a match was found for ([QuickPalette.swift:225-239](../../../Sources/GraphiteUI/QuickPalette.swift#L225-L239)).
  - Settings writes use a change counter ([SettingsView.swift:974-983](../../../Sources/GraphiteUI/SettingsView.swift#L974-L983)).
- **Why it matters:** Each is correct where it stands, but each new async feature invents its own, and a reviewer has to verify each one separately.
- **Fix direction:**
  - One `LatestRequest` primitive, a token generator plus an `isCurrent(token)` check, in the allow-listed primitives file.
  - The five sites use it.

#### CC-SHELL-04 `try?` swallows failures the person needs to know about
- **Severity:** Medium
- **Evidence (11 sites, counted by reading):**
  - The Mac quit save: `try? await workspace.saveOpenDocuments()` ([GraphiteMacScenes.swift:55](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L55)); see BUG-SHELL-03.
  - The last save before a vault switch drops the sessions: `try? await document.saveAllChanges()` ([WorkspaceModel.swift:302](../../../Sources/GraphiteUI/WorkspaceModel.swift#L302)).
  - The copy taken before `graphite://new?…&overwrite` overwrites a note: `_ = try? fileRecovery.takeSnapshot` ([WorkspaceDeepLinks.swift:157](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L157), [166](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L166)). The overwrite then proceeds without a copy, although [Architecture.md:135](../../../Docs/Architecture.md) says `overwrite` keeps a File recovery copy first.
  - Restore's copy of the current version ([WorkspaceRecovery.swift:56](../../../Sources/GraphiteUI/WorkspaceRecovery.swift#L56), [64](../../../Sources/GraphiteUI/WorkspaceRecovery.swift#L64)).
  - Snapshots before deleting ([WorkspaceRecovery.swift:35](../../../Sources/GraphiteUI/WorkspaceRecovery.swift#L35)).
  - "Delete All Snapshots" ([SettingsView.swift:664](../../../Sources/GraphiteUI/SettingsView.swift#L664)).
  - File recovery reads ([FileRecoverySheet.swift:60](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L60), [101](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L101), [145](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L145)).
- **Why it matters:**
  - RULES.md: "A failed save retains recoverable work" and "Do not … ignore failed saves".
  - A destructive change whose backup failed proceeds without telling anyone.
- **Fix direction:**
  - A backup that fails stops the destructive step, or asks first.
  - Quit and switch paths surface a failed save (BUG-SHELL-03).
  - Each remaining `try?` gets a same-line reason.

#### CC-SHELL-05 Eleven pieces of logic are implemented twice
- **Severity:** Medium
- **Evidence:**

  | Logic | Copies |
  | --- | --- |
  | Comparable path | [WorkspaceModel.swift:1351-1353](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1351-L1353), [VaultLibrary.swift:63-65](../../../Sources/GraphiteUI/VaultLibrary.swift#L63-L65), inline at [WorkspaceDeepLinks.swift:98](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L98) and [104](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L104) |
  | Pasteboard copy | [WorkspacePanes.swift:592-600](../../../Sources/GraphiteUI/WorkspacePanes.swift#L592-L600), [VaultSidebar.swift:811-818](../../../Sources/GraphiteUI/VaultSidebar.swift#L811-L818) |
  | Highlighted fuzzy title | [QuickPalette.swift:153-168](../../../Sources/GraphiteUI/QuickPalette.swift#L153-L168), [EditorCompletion.swift:401-416](../../../Sources/GraphiteUI/EditorCompletion.swift#L401-L416) |
  | Expand the folders above a path | [WorkspaceFileManagement.swift:286-294](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L286-L294), [WorkspaceBookmarks.swift:82-90](../../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L82-L90) |
  | Unreserved character set for Markdown links | [WorkspaceModel.swift:951](../../../Sources/GraphiteUI/WorkspaceModel.swift#L951), [WorkspaceMentions.swift:66](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L66) |
  | File-tree extension suffix | [VaultSidebar.swift:738-743](../../../Sources/GraphiteUI/VaultSidebar.swift#L738-L743), [MacFileTree.swift:329-335](../../../Sources/GraphiteUI/MacFileTree.swift#L329-L335) |
  | Kind icon (the two disagree for `.media`) | [QuickPalette.swift:306-318](../../../Sources/GraphiteUI/QuickPalette.swift#L306-L318), [VaultSidebar.swift:831-842](../../../Sources/GraphiteUI/VaultSidebar.swift#L831-L842) |
  | Strip a typed extension on rename | [VaultSidebar.swift:1041-1045](../../../Sources/GraphiteUI/VaultSidebar.swift#L1041-L1045), [GraphiteRootView.swift:291-293](../../../Sources/GraphiteUI/GraphiteRootView.swift#L291-L293) |
  | Note text decoding | `String(data:encoding:.utf8)` with `Data(text.utf8)` writes at [WorkspaceDeepLinks.swift:165-167](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L165-L167), [WorkspaceRecovery.swift:33](../../../Sources/GraphiteUI/WorkspaceRecovery.swift#L33), [64-68](../../../Sources/GraphiteUI/WorkspaceRecovery.swift#L64-L68), [WorkspaceTemplates.swift:29](../../../Sources/GraphiteUI/WorkspaceTemplates.swift#L29), [51](../../../Sources/GraphiteUI/WorkspaceTemplates.swift#L51); versus `NoteTextEncoding` at [WorkspaceMentions.swift:78-82](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L78-L82), [WorkspaceReadingTasks.swift:21-24](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L21-L24), [WorkspaceTagsAndProperties.swift:80-83](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L80-L83) |
  | Alert helper | `errorAlert` titled "Graphite" ([VaultSwitcher.swift:346-352](../../../Sources/GraphiteUI/VaultSwitcher.swift#L346-L352)), `messageAlert` titled with the first sentence ([MessageAlert.swift:6-41](../../../Sources/GraphiteUI/MessageAlert.swift#L6-L41)) |
  | Tab title | [WorkspacePanes.swift:295-300](../../../Sources/GraphiteUI/WorkspacePanes.swift#L295-L300), [TabSwitcher.swift:102-104](../../../Sources/GraphiteUI/TabSwitcher.swift#L102-L104) (BUG-SHELL-06) |

- **Why it matters:**
  - The copies already disagree: the media icon differs, the tab title differs, the alert title differs.
  - The deep-link `append`/`overwrite` path and the Restore path write notes as plain UTF-8 bytes, while every other rewrite in the workspace keeps the byte order mark through `NoteTextEncoding`. How `String(data:encoding:)` treats a byte order mark was not settled by reading, so this is recorded as a rule split, not as a bug.
- **Fix direction:** Pick one owner for each rule and delete the copies. Every note read and write in the shell goes through `NoteTextEncoding`.

#### CC-SHELL-06 The model writes user-facing text, and views have no string catalogue
- **Severity:** Medium
- **Evidence:**
  - Index status words are built in the model ([WorkspaceModel.swift:522](../../../Sources/GraphiteUI/WorkspaceModel.swift#L522), [536](../../../Sources/GraphiteUI/WorkspaceModel.swift#L536), [539](../../../Sources/GraphiteUI/WorkspaceModel.swift#L539), [587](../../../Sources/GraphiteUI/WorkspaceModel.swift#L587), [592-593](../../../Sources/GraphiteUI/WorkspaceModel.swift#L592-L593)).
  - So is "Open to the Left/Right" ([WorkspaceTabs.swift:93-95](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L93-L95)).
  - So are the attachment-location descriptions ([WorkspaceModel.swift:995-1006](../../../Sources/GraphiteUI/WorkspaceModel.swift#L995-L1006)).
  - 82 `errorMessage` sentences are written in the model (SRP-SHELL-03).
  - Views use literal strings throughout. For example, `Text("No file is open")` ([WorkspacePanes.swift:670](../../../Sources/GraphiteUI/WorkspacePanes.swift#L670)).
- **Why it matters:**
  - Wording changes edit the model.
  - Tests assert on sentences.
  - Localisation would have to reach into domain code.
- **Fix direction:**
  - The model exposes typed status (`IndexStatus.scanning`, `.paused`, `.needsAttention`, `.ready(fileCount:pendingCount:)`) and typed errors.
  - One presenter and a string catalogue make the words.

#### CC-SHELL-07 Literal durations, caps and sizes in logic
- **Severity:** Low
- **Evidence (counted by reading; named constants elsewhere in the area are not listed):**
  - Durations:
    - 250 ms ([GraphiteRootView.swift:472](../../../Sources/GraphiteUI/GraphiteRootView.swift#L472));
    - 180 ms search debounce ([VaultSidebar.swift:172](../../../Sources/GraphiteUI/VaultSidebar.swift#L172));
    - 100 ms × 10 reveal ([VaultSidebar.swift:129-130](../../../Sources/GraphiteUI/VaultSidebar.swift#L129-L130));
    - 350 ms ([VaultSidebar.swift:1021](../../../Sources/GraphiteUI/VaultSidebar.swift#L1021));
    - 60 ms switcher debounce ([QuickPalette.swift:232](../../../Sources/GraphiteUI/QuickPalette.swift#L232));
    - 300 ms progress delay ([WorkspacePanes.swift:822](../../../Sources/GraphiteUI/WorkspacePanes.swift#L822));
    - 40 × 250 ms ([WorkspaceDeepLinks.swift:82-83](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L82-L83)).
  - Caps:
    - 20 recent files in the switcher ([QuickPalette.swift:246](../../../Sources/GraphiteUI/QuickPalette.swift#L246));
    - 10 recent paths and a 1.5 bonus ([QuickPalette.swift:251-254](../../../Sources/GraphiteUI/QuickPalette.swift#L251-L254));
    - 8 recent commands, written twice ([QuickPalette.swift:358](../../../Sources/GraphiteUI/QuickPalette.swift#L358));
    - 5 notes listed in the property-rename error ([WorkspaceTagsAndProperties.swift:97-98](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L97-L98));
    - the 12...28 text size range ([GraphitePreferences.swift:380](../../../Sources/GraphiteUI/GraphitePreferences.swift#L380)).
  - Sizes: tab width 220, written twice ([WorkspacePanes.swift:183](../../../Sources/GraphiteUI/WorkspacePanes.swift#L183), [318](../../../Sources/GraphiteUI/WorkspacePanes.swift#L318)).
- **Why it matters:** The timings are tuning choices with reasons that live only in the developer's memory, and the duplicated ones drift.
- **Fix direction:** Named constants with units, next to the rule they serve, as `externalRefreshDelay` already is ([WorkspaceModel.swift:1272-1275](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1272-L1275)).

#### CC-SHELL-08 Comments narrate incidents and dates
- **Severity:** Low
- **Evidence (9 comments, counted by reading):**
  - [WorkspaceModel.swift:501-504](../../../Sources/GraphiteUI/WorkspaceModel.swift#L501-L504) ("measured 2026-10-16").
  - [VaultSidebar.swift:576-581](../../../Sources/GraphiteUI/VaultSidebar.swift#L576-L581) and [589-592](../../../Sources/GraphiteUI/VaultSidebar.swift#L589-L592).
  - [MacFileTree.swift:9-13](../../../Sources/GraphiteUI/MacFileTree.swift#L9-L13).
  - [GraphitePreferences.swift:303-307](../../../Sources/GraphiteUI/GraphitePreferences.swift#L303-L307).
  - [App/GraphiteApp.swift:26-29](../../../App/GraphiteApp.swift#L26-L29) ("reported by the owner, 2026-10-13").
  - [GraphiteRootView.swift:64-66](../../../Sources/GraphiteUI/GraphiteRootView.swift#L64-L66) and [152-153](../../../Sources/GraphiteUI/GraphiteRootView.swift#L152-L153).
  - [GraphiteMacScenes.swift:42-44](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L42-L44).
- **Why it matters:**
  - The rule each comment protects is valuable and must stay.
  - The dates and incident stories belong in commit messages and regression-test names.
- **Fix direction:** Rewrite each comment as the present-tense rule ("Rows are one view each so the outline view finds a row by position"), and keep the measurement in the test that pins it.

#### CC-SHELL-09 Shell tests are named after audit rounds, share the process's defaults, poll with sleeps and assert on text
- **Severity:** Medium
- **Evidence:**
  - Test classes named after rounds:
    - `UiWorkspaceModelFixTests` ([UiWorkspaceModelFixTests.swift:12](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L12));
    - `UiWorkspaceAreaHandoffTests`, `UiSidebarPaletteFixTests`, `UiFileManagementFixTests`, `BugFixRegressionTests`.
  - `UiRootSettingsTests` mixes image decoding, drawing drafts, vault settings, palettes and paper sizes ([UiRootSettingsTests.swift:21-351](../../../Tests/GraphiteUITests/UiRootSettingsTests.swift#L21-L351)).
  - Tests use the standard defaults ([UiWorkspaceModelFixTests.swift:17-37](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L17-L37)).
  - They poll with sleeps ([UiWorkspaceModelFixTests.swift:57-66](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L57-L66), [UiRootSettingsTests.swift:212-217](../../../Tests/GraphiteUITests/UiRootSettingsTests.swift#L212-L217)).
  - They assert on message text ([UiWorkspaceModelFixTests.swift:399](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L399), [UiRootSettingsTests.swift:55-56](../../../Tests/GraphiteUITests/UiRootSettingsTests.swift#L55-L56)).
  - Test doc comments say "used to" ([UiWorkspaceModelFixTests.swift:94](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L94), [113](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L113), [218](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L218), [366](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L366)).
- **Why it matters:**
  - A failing test does not say which production type broke.
  - Tests can fail through another test's leftover preferences.
  - Wording edits break them.
- **Fix direction:**
  - Once DIP-SHELL-01 lands, rename the tests after the type they pin (`VaultSwitcherTests`, `TabWorkspaceTests`, `FileManagementTests`).
  - Inject defaults and a clock.
  - Await events instead of polling.
  - Assert on typed outcomes.

#### CC-SHELL-10 Large multi-concept files and small hygiene issues
- **Severity:** Low
- **Evidence:**
  - [VaultSidebar.swift](../../../Sources/GraphiteUI/VaultSidebar.swift) declares 20 types (counted by reading), among them sheets, drag types and the file tree.
  - [WorkspacePanes.swift](../../../Sources/GraphiteUI/WorkspacePanes.swift) declares 14, including `Pasteboard` ([592](../../../Sources/GraphiteUI/WorkspacePanes.swift#L592)) and `DelayedProgressView` ([816](../../../Sources/GraphiteUI/WorkspacePanes.swift#L816)).
  - `import GraphiteApple` appears twice ([GraphitePreferences.swift:5](../../../Sources/GraphiteUI/GraphitePreferences.swift#L5), [7](../../../Sources/GraphiteUI/GraphitePreferences.swift#L7)).
  - Markdown and YAML are embedded in Swift strings: the new base file ([WorkspaceModel.swift:786](../../../Sources/GraphiteUI/WorkspaceModel.swift#L786)) and inserted blocks ([WorkspaceCommands.swift:241-244](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L241-L244)).
  - Search queries are built from text in four places ([WorkspaceMentions.swift:46](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L46), [WorkspaceTagsAndProperties.swift:36](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L36), [41-42](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L41-L42), [WorkspaceGraph.swift:29](../../../Sources/GraphiteUI/WorkspaceGraph.swift#L29)).
- **Why it matters:**
  - Search-query escaping rules are spread over four call sites.
  - File-level navigation is slow in 1,000-line files.
- **Fix direction:**
  - One concept per file.
  - A `SearchQuery` builder in Core (`.tag(_)`, `.property(_)`, `.content(_)`) that owns quoting.
  - Default file contents as named constants in the feature that owns the format.

## 5. Defects and latent bugs

#### BUG-SHELL-01 A `graphite://read` link whose file does not resolve reads the note that is already open aloud
- **Trigger:** Another app (Shortcuts, a browser) opens `graphite://read?file=<name>` and no file in the vault matches `<name>`. The same happens when the link names a PDF.
- **Path:**
  1. `.onOpenURL` passes the link to the model ([GraphiteRootView.swift:224-226](../../../Sources/GraphiteUI/GraphiteRootView.swift#L224-L226)).
  2. `handle` matches `.read(let file)` and calls `openLinkedFile(file)` ([WorkspaceDeepLinks.swift:39-40](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L39-L40)).
  3. `openLinkedFile` polls the index for up to about 10 s, sets `errorMessage` and returns without opening anything ([WorkspaceDeepLinks.swift:80-89](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L80-L89)).
  4. Back in `handle`, the next guard is only the Read Aloud switch ([WorkspaceDeepLinks.swift:41-44](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L41-L44)).
  5. `guard let session = markdownSession` takes the focused tab's note ([WorkspaceDeepLinks.swift:45](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L45); `markdownSession` is the active document, [WorkspaceModel.swift:101](../../../Sources/GraphiteUI/WorkspaceModel.swift#L101)).
  6. `readAloud.readMarkdown(session.text, path: session.path)` starts reading that note, folded sections included ([WorkspaceDeepLinks.swift:46](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L46)).
- **Effect:** The alert says no file matches, and at the same time Graphite reads a different note aloud. No check compares the session's path with the requested file. When the link names a PDF, nothing is read and no message says why.
- **Platforms / reach:** iPad, iPhone, Mac; the normal deep-link path.
- **Confidence:** Traced.

#### BUG-SHELL-02 Removing a vault from the list leaves its folded-heading records, which name its notes, in the app's preferences
- **Trigger:** In the vault manager, the person chooses Remove from List (or swipes Remove) on a vault that is not open.
- **Path:**
  1. `KnownVaultRow`'s remove action calls `workspace.removeFromVaultList(vault)` ([VaultSwitcher.swift:154-156](../../../Sources/GraphiteUI/VaultSwitcher.swift#L154-L156), [214-218](../../../Sources/GraphiteUI/VaultSwitcher.swift#L214-L218)).
  2. `removeFromVaultList` removes the keys for expanded folders, recent files and the tab layout, then the places ([WorkspaceModel.swift:254-257](../../../Sources/GraphiteUI/WorkspaceModel.swift#L254-L257)).
  3. The folds key `"GraphiteFolds." + uuid` is declared `private` in another file ([WorkspaceFolds.swift:7-9](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L7-L9)) and is not removed. The dictionary maps each note path to its folded keys ([WorkspaceFolds.swift:11-19](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L11-L19)).
  4. The identifier is never reused: opening the folder again makes a new one ([WorkspaceModel.swift:253](../../../Sources/GraphiteUI/WorkspaceModel.swift#L253)). The entry is therefore orphaned for good.
- **Effect:**
  - The device keeps a list of the removed vault's note paths in the app's preferences, although the code comment ([WorkspaceModel.swift:242-243](../../../Sources/GraphiteUI/WorkspaceModel.swift#L242-L243)) and the vault manager's footer ([VaultSwitcher.swift:172](../../../Sources/GraphiteUI/VaultSwitcher.swift#L172)) say the vault is forgotten.
  - The test that pins removal checks only three key families ([UiWorkspaceModelFixTests.swift:158](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L158)).
  - Drawing drafts saved for that vault are not removed either. The draft store has no per-vault removal ([DrawingEditorDraftStore.swift:84-115](../../../Sources/GraphiteUI/DrawingEditorDraftStore.swift#L84-L115)). Whether they should be deleted, rather than offered once, is a product decision. They are user work, so they are not counted as part of this defect.
- **Platforms / reach:** iPad, iPhone, Mac; normal path.
- **Confidence:** Traced.

#### BUG-SHELL-03 Quitting on the Mac discards unsaved edits of a note that cannot be saved, without asking
- **Trigger:** A note has unsaved text and is in conflict with another app's change. Or any open document's save fails, or takes longer than 5 seconds (iCloud Drive). The person presses ⌘Q.
- **Path:**
  1. `applicationShouldTerminate` returns `.terminateLater` and starts two tasks ([GraphiteMacScenes.swift:51-62](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L51-L62)).
  2. The first runs `try? await workspace.saveOpenDocuments()` ([GraphiteMacScenes.swift:55](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L55)). `saveOpenDocuments` tries every document and throws the first failure ([WorkspaceModel.swift:487-493](../../../Sources/GraphiteUI/WorkspaceModel.swift#L487-L493)).
  3. A conflicted note's `save()` throws `.conflict` before writing anything ([MarkdownSession.swift:154](../../../Sources/GraphiteUI/MarkdownSession.swift#L154)).
  4. The `try?` drops that error, and `reply.allowTermination()` runs ([GraphiteMacScenes.swift:56](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L56)).
  5. Independently, the second task allows termination after 5 s, even while a save is still running ([GraphiteMacScenes.swift:58-61](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L58-L61)).
- **Effect:**
  - The app quits. The text held only in the session is lost: no prompt appears and no ` Graphite edits` copy is written, although `saveSeparateCopy` exists for exactly this state ([MarkdownSession.swift:223-228](../../../Sources/GraphiteUI/MarkdownSession.swift#L223-L228)).
  - This contradicts RULES.md, which says a failed save must keep recoverable work.
  - Plugin file views (`saveOpenFileViews`) are not saved on this path either, while the iPad's leave-screen path saves them ([GraphiteRootView.swift:495](../../../Sources/GraphiteUI/GraphiteRootView.swift#L495)).
- **Platforms / reach:** Mac only; the normal quit path.
- **Confidence:** Partly traced. The quit-reply path is traced. Not settled by reading: whether macOS delivers a scene-phase change before termination, which would also run `saveBeforeLeavingScreen` ([GraphiteRootView.swift:227-237](../../../Sources/GraphiteUI/GraphiteRootView.swift#L227-L237)). That path only reports the failure in an alert and does not block quitting.

#### BUG-SHELL-04 "Reveal current file" from the command palette or a tab's menu neither shows a hidden sidebar nor scrolls to the file
- **Trigger:** The person runs "Files: Reveal current file in navigation" from the command palette, or "Reveal in Sidebar" from a tab's context menu, while the sidebar is hidden or scrolled elsewhere, or while a community plugin's sidebar view is chosen.
- **Path:**
  1. The palette command calls `workspace.revealCurrentFile()` ([WorkspaceCommands.swift:122](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L122)). The tab menu calls it after `activateTab` ([WorkspacePanes.swift:286-289](../../../Sources/GraphiteUI/WorkspacePanes.swift#L286-L289)).
  2. `revealCurrentFile` writes the panel key, clears the search and inserts the parent folders into `expandedFolders`. That is all it does ([WorkspaceFileManagement.swift:286-294](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L286-L294)).
  3. The root view shows the sidebar only when `searchFocusRequest` or a plugin's `sidebarViewRequest` changes ([GraphiteRootView.swift:213-215](../../../Sources/GraphiteUI/GraphiteRootView.swift#L213-L215)). Neither changes here.
  4. The scroll target `fileToReveal` is private sidebar state, set only by the sidebar's own options menu ([VaultSidebar.swift:61](../../../Sources/GraphiteUI/VaultSidebar.swift#L61), [247](../../../Sources/GraphiteUI/VaultSidebar.swift#L247), [471-477](../../../Sources/GraphiteUI/VaultSidebar.swift#L471-L477)). The Mac tree reveals only through that binding ([MacFileTree.swift:42-45](../../../Sources/GraphiteUI/MacFileTree.swift#L42-L45)).
  5. When a plugin sidebar view is chosen, `sidebarContent` keeps showing it, because `shownSidebarViewIdentifier` is not cleared ([VaultSidebar.swift:265-268](../../../Sources/GraphiteUI/VaultSidebar.swift#L265-L268), [81-87](../../../Sources/GraphiteUI/VaultSidebar.swift#L81-L87)).
- **Effect:**
  - With the sidebar hidden (an iPad window in portrait, focus mode, or a phone), the command does nothing visible.
  - With it visible, the folders open but the file's row can stay off screen.
  - With a plugin view chosen, the file tree does not appear at all.
- **Platforms / reach:** iPad, iPhone, Mac; normal path.
- **Confidence:** Traced.

#### BUG-SHELL-05 File Recovery says "No Snapshots Yet" when its list cannot be read, and spins forever when a snapshot's text cannot be read
- **Trigger:** `FileRecoveryStore.recoverableNotes()`, `snapshots(for:)` or `text(of:)` throws: for example, the snapshot folder or file is unreadable.
- **Path:**
  - **Note list:** the sheet's `.task` runs `(try? fileRecovery.recoverableNotes()) ?? []` and sets `hasLoaded = true` ([FileRecoverySheet.swift:59-61](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L59-L61)). The list shows "No Snapshots Yet" ([FileRecoverySheet.swift:25-28](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L25-L28)).
  - **Snapshot list:** the same pattern ([FileRecoverySheet.swift:99-102](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L99-L102)).
  - **Preview:** `text = await … { try? fileRecovery.text(of:) }` leaves `text` nil ([FileRecoverySheet.swift:142-146](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L142-L146)). The overlay then shows a `ProgressView` for as long as `text == nil` ([FileRecoverySheet.swift:124](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L124)), and Copy and Restore stay disabled ([FileRecoverySheet.swift:128-131](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L128-L131)).
- **Effect:** A person looking for an earlier version of a note is told none exists, or waits forever on a spinner. No error explains either.
- **Platforms / reach:** iPad, iPhone, Mac; failure path only.
- **Confidence:** Partly traced. The outcome given a thrown error is traced. The conditions under which `FileRecoveryStore` throws were not read (Core area).

#### BUG-SHELL-06 The phone's tab switcher lists a tab showing a community plugin view as "New Tab"
- **Trigger:** In a compact width (iPhone, or a narrow iPad window), a plugin view opens in a tab, and the person opens the tab switcher from the bottom bar.
- **Path:**
  1. The bottom bar's tab button opens `TabSwitcher` ([GraphiteRootView.swift:386-388](../../../Sources/GraphiteUI/GraphiteRootView.swift#L386-L388)).
  2. `row(for:)` uses `title(of:)` and an icon chosen from `tab.path` ([TabSwitcher.swift:54](../../../Sources/GraphiteUI/TabSwitcher.swift#L54), [59](../../../Sources/GraphiteUI/TabSwitcher.swift#L59)).
  3. `title(of:)` returns "New Tab" whenever `tab.path` is nil ([TabSwitcher.swift:102-104](../../../Sources/GraphiteUI/TabSwitcher.swift#L102-L104)).
  4. The tab bar names the same tab after its plugin view ([WorkspacePanes.swift:295-300](../../../Sources/GraphiteUI/WorkspacePanes.swift#L295-L300)).
- **Effect:** Plugin tabs look like empty tabs in the only tab list a phone has, so the person cannot tell which tab holds the plugin view.
- **Platforms / reach:** iPhone and compact iPad windows; normal path.
- **Confidence:** Traced.

## 6. What to keep

| Design | Evidence | Why it is sound |
| --- | --- | --- |
| Derived tab state is projected from `layout` and written only when it changes | [WorkspaceModel.swift:40-52](../../../Sources/GraphiteUI/WorkspaceModel.swift#L40-L52), [91-104](../../../Sources/GraphiteUI/WorkspaceModel.swift#L91-L104); test [UiWorkspaceModelFixTests.swift:527-550](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L527-L550) | Views that show only the focused file are not redrawn on each frame of a divider drag. No caller has to remember to update `selection`. Any split must keep these projections and their write-only-on-change guards. |
| `TabLayout` is a Core value type; the model only adds documents | [WorkspaceTabs.swift:84-216](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L84-L216) delegates every layout decision to `layout.*` | Tab rules are unit-testable without UI (`TabLayoutTests`). `TabWorkspace` should wrap it, not absorb it. |
| Pure, tested decision helpers | `ExternalChangeRefresh` [WorkspaceModel.swift:1405-1453](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1405-L1453); `externalRefreshDeadline` [1281-1283](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1281-L1283); `insertionRange` [904-912](../../../Sources/GraphiteUI/WorkspaceModel.swift#L904-L912); `pastedImageStem` / `recordingTimestamp` with injected dates [936-940](../../../Sources/GraphiteUI/WorkspaceModel.swift#L936-L940), [1174-1177](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1174-L1177); `MessageAlert.parts` [MessageAlert.swift:26-34](../../../Sources/GraphiteUI/MessageAlert.swift#L26-L34); `SettingsFolderPath` [SettingsView.swift:1045-1058](../../../Sources/GraphiteUI/SettingsView.swift#L1045-L1058); `PaletteColorNames` [SettingsView.swift:447-465](../../../Sources/GraphiteUI/SettingsView.swift#L447-L465); `CustomPaperSize` [GraphiteRootView.swift:632-640](../../../Sources/GraphiteUI/GraphiteRootView.swift#L632-L640); `TextComparisonRows` [ConflictVersionsSheet.swift:364-413](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L364-L413) | These are "decide, then do" already in place. Move them with their tests, unchanged. |
| A stale result never lands in a newer state | Run identifier [WorkspaceModel.swift:523-556](../../../Sources/GraphiteUI/WorkspaceModel.swift#L523-L556); request identifier [WorkspaceTabs.swift:336-339](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L336-L339), [381](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L381); vault guards `store === refreshedStore` [WorkspaceModel.swift:1245](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1245), `self.index === index` [571](../../../Sources/GraphiteUI/WorkspaceModel.swift#L571) | Each async step re-checks that it still belongs to the current vault or request. Unify the mechanism (CC-SHELL-03) without dropping any check. |
| Typed text is never lost on navigation, close, move or switch | `saveBeforeClosing` repeat loop [WorkspaceTabs.swift:226-239](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L226-L239); `closeGroup` loop [193-204](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L193-L204); `saveAllChanges` before a swap [WorkspaceTabs.swift:378-380](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L378-L380); edits during a move [WorkspaceFileManagement.swift:142-150](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L142-L150), [206-228](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L206-L228); delete only after save and snapshot [263-283](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L263-L283); tests [UiFileManagementFixTests.swift:99-149](../../../Tests/GraphiteUITests/UiFileManagementFixTests.swift#L99-L149), [UiWorkspaceModelFixTests.swift:134-149](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L134-L149) | This is the OBJECTIVE.md contract ("never discard unsaved user work"), made concrete. Every extracted workflow must keep these loops and orderings. |
| Embeds are refused, not forced, after slow writes | [WorkspaceModel.swift:875-891](../../../Sources/GraphiteUI/WorkspaceModel.swift#L875-L891), [1052-1066](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1052-L1066); retry on a taken name [922-933](../../../Sources/GraphiteUI/WorkspaceModel.swift#L922-L933); tests [UiWorkspaceModelFixTests.swift:325-400](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L325-L400) | The file is kept and the person is told, instead of overwriting their text or inserting into a conflicted note. |
| Moves are asked about one at a time and queued | `PendingMove` / `QueuedMoves` [WorkspaceFileManagement.swift:6-30](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L6-L30), [84-135](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L84-L135); a move waits for a complete index [96-101](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L96-L101) | Links are never silently left broken, and a multi-item drop does not stack dialogs. |
| Conflict-version feature structure | Model [ConflictVersionsSheet.swift:8-65](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L8-L65); wording enum [174-201](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L174-L201); bounded batch queue [WorkspaceConflictVersions.swift:25-63](../../../Sources/GraphiteUI/WorkspaceConflictVersions.swift#L25-L63); injected `ConflictVersionStore` [WorkspaceModel.swift:165](../../../Sources/GraphiteUI/WorkspaceModel.swift#L165); stamp check [WorkspaceConflictVersions.swift:101-115](../../../Sources/GraphiteUI/WorkspaceConflictVersions.swift#L101-L115), [142-154](../../../Sources/GraphiteUI/WorkspaceConflictVersions.swift#L142-L154) | Already the target shape: a feature model, a seam with a test double, bounded background work, and refusal on a stale listing. Use it as the template for the other extractions. |
| Tolerant persisted list | `VaultLibrary` keeps unreadable entries and an unreadable whole list [VaultLibrary.swift:67-109](../../../Sources/GraphiteUI/VaultLibrary.swift#L67-L109); legacy bookmark adopted only once it resolves [114-131](../../../Sources/GraphiteUI/VaultLibrary.swift#L114-L131); hermetic tests [UiFileManagementFixTests.swift:260-336](../../../Tests/GraphiteUITests/UiFileManagementFixTests.swift#L260-L336) | "Unreadable data is moved aside, never overwritten" is already implemented. Keep it. |
| `DocumentPlaceStore`: read once, write on change, injected defaults | [WorkspacePlaces.swift:79-112](../../../Sources/GraphiteUI/WorkspacePlaces.swift#L79-L112); tests [DocumentPlaceStoreTests.swift:32-73](../../../Tests/GraphiteUITests/DocumentPlaceStoreTests.swift#L32-L73) | This is the pattern `VaultDeviceMemory` should generalise to the other four per-vault key families. |
| Places taken synchronously when the scene goes inactive | [GraphiteRootView.swift:228-231](../../../Sources/GraphiteUI/GraphiteRootView.swift#L228-L231) | The reason is in the comment: by the time a save task runs, iPadOS can have resized the window. `SceneLifecycleSaver` must keep this synchronous step first. |
| Settings writes serialised, each building on the last | `VaultSettingsChanges` [SettingsView.swift:960-986](../../../Sources/GraphiteUI/SettingsView.swift#L960-L986); `saveSettings(_, changedFrom:)` writes only changed keys [WorkspaceModel.swift:405-407](../../../Sources/GraphiteUI/WorkspaceModel.swift#L405-L407); tests [UiRootSettingsTests.swift:221-266](../../../Tests/GraphiteUITests/UiRootSettingsTests.swift#L221-L266) | Quick taps are not lost, and Obsidian's concurrent edits to `app.json` survive. |
| Large-vault file tree performance | `FileTreeRows` and `VaultEntryRow` as single `Equatable` views [VaultSidebar.swift:572-645](../../../Sources/GraphiteUI/VaultSidebar.swift#L572-L645); Mac outline view with node reuse [MacFileTree.swift:14-184](../../../Sources/GraphiteUI/MacFileTree.swift#L14-L184); per-hex accent cache [GraphitePreferences.swift:303-315](../../../Sources/GraphiteUI/GraphitePreferences.swift#L303-L315) | Measured fixes for vaults of about 25,000 files at the root. A refactor of the sidebar must keep the row identity (`entry.path.rawValue`), the `.equatable()` boundary and the unchanged-listing short-circuit [WorkspaceModel.swift:505](../../../Sources/GraphiteUI/WorkspaceModel.swift#L505). |
| Mac quit answers once | `TerminationReply` [GraphiteMacScenes.swift:66-77](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L66-L77) | Correct once-only primitive. Keep it, and fix only the swallowed failure (BUG-SHELL-03). |
| Mac single window | [GraphiteMacScenes.swift:23-28](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L23-L28) | Two workspaces on one index file would fail each other's writes. This constraint must survive any scene refactor. |
| Passive touch observer and presented-screen observer | [WorkspacePanes.swift:751-813](../../../Sources/GraphiteUI/WorkspacePanes.swift#L751-L813); [PresentedScreenObserver.swift:27-86](../../../Sources/GraphiteUI/PresentedScreenObserver.swift#L27-L86) | Both observe without competing with the editor's or PencilKit's gestures, and `isolated deinit` stops the observer. These protect Pencil and editor responsiveness. |
| Palette closes before it acts | `QuickPalette.perform` [QuickPalette.swift:193-196](../../../Sources/GraphiteUI/QuickPalette.swift#L193-L196); test [UiSidebarPaletteFixTests.swift:86](../../../Tests/GraphiteUITests/UiSidebarPaletteFixTests.swift#L86) | A command that opens another palette is not undone by the close. |
| `WorkspaceFocusMode` value type | [WorkspaceFocusMode.swift:4-23](../../../Sources/GraphiteUI/WorkspaceFocusMode.swift#L4-L23); tests [WorkspaceFocusModeTests.swift:6-46](../../../Tests/GraphiteUITests/WorkspaceFocusModeTests.swift#L6-L46) | Already a small, tested state machine. `WorkspaceWindowLayout` should embed it. |

## 7. Blueprint for this area

### Target shape

| Type | Single responsibility | Seam |
| --- | --- | --- |
| `WorkspaceDependencies` | Values passed in by the composition root: defaults store, clock, vault library, preferences, place store, conflict store, recorder, plugin host factory, vault opener (store, index, monitor). | Initializer argument; tests pass a private defaults suite and doubles that keep production semantics. |
| `OpenVault` (value) + `VaultSwitcher` | Identity and I/O handles of the open vault; opening, switching, restoring, removing; the switch ordering in SHELL-INV-09. | `VaultScoped` protocol (`vaultWillClose()`, `vaultDidOpen(_ vault: OpenVault)`). The switcher walks its conformers and names no feature. |
| `VaultDeviceMemory` | Every per-vault device key (expanded folders, recent files, tab layout, places, folds), behind a typed registry; `forgetVault`. | Injected defaults store. |
| `VaultIndexing` | Scan, rebuild, incremental refresh, status as a typed value. | `VaultScoped`. |
| `ExternalChangeCoordinator` | Debounce, classify (`ExternalChangeRefresh`), publish typed change events. | Subscribers: tabs, conflicts, appearance, index, file list. |
| `VaultFileList` | Root listing, expanded folders, reveal (with a scroll target the sidebar observes). | Read by both file trees. |
| `VaultSearch` | Query, debounce, pages, sort. | — |
| `TabWorkspace` | `TabLayout` + documents, activation, closing, history, PDF release, layout persistence through `VaultDeviceMemory`. | `DocumentOpener` registry keyed by `DocumentKind` (one entry per kind). |
| `FileManagement` | Move, rename, copy, delete, the link-update question queue. | — |
| `NoteCreation`, `AttachmentPublisher`, `DrawingWorkflow`, `RecordingWorkflow` | One workflow each; every write ends with one `afterWrite(paths:)` call that refreshes index and file list. | — |
| `ConflictVersionTracker`, `FileRecoveryModel`, `VaultAppearanceModel`, `BookmarksModel`, `GraphAndMapCache` | The existing extensions, given their own state. | `VaultScoped`. |
| `WorkspaceAlerts` | A queue of typed alerts and notices; one presenter turns them into words. | — |
| `WorkspaceCommandCatalogue` | Each command declared once: identifier, title, shortcut, availability, action, placement. | Rendered by both the palette and the menu bar. |
| `CreationCatalogue`, `SidebarPanel` descriptors, `DocumentKindHandler` descriptors | Each "add a kind or panel" is one enum case plus one descriptor. | — |
| `WorkspaceWindowLayout` (`@Observable`) | Columns, inspector, focus mode, active palette, window intents (`WindowActions` today). | — |
| `SceneLifecycleSaver` | Remember places, save, keep alive in the background, Mac quit; one policy for a failed save. | — |
| `PluginWorkspaceAccess` | The about 15 capabilities the plugin host uses (ISP-SHELL-02). | Protocol, because the host's tests need a fake; implemented by the split models. |

`Workspace`, the composition object, only creates and holds these and holds no logic. Views take the narrow models. No protocol is added where there is a single implementation and no test need, except `PluginWorkspaceAccess` and `DocumentSession`.

### Ordered steps (each leaves the app building and behaving the same)
1. **Typed per-vault key registry.**
   - Add `VaultDeviceMemory` with the five key families, keeping the key strings byte for byte (SHELL-INV-01).
   - Move the `didSet` persistence of `expandedFolders` and `recentFiles`, plus folds and tab layout, onto it.
   - `forgetVault` removes every registered family. This fixes BUG-SHELL-02; add the folds key to the removal test.
2. **Inject dependencies.** Add `WorkspaceModel.init(dependencies:)`, with `WorkspaceDependencies.live` used by `GraphiteRootView` and `GraphiteMacScenes`. Migrate the tests to a private defaults suite, and delete the `UserDefaults.standard` save/restore in the test setup.
3. **Fix BUG-SHELL-03 inside the existing delegate.** On a failed save, reply `false` and present the alert, or write separate copies, then quit.
4. **Extract `WorkspaceAlerts`.** Keep `errorMessage` as a computed bridge at first. Convert callers file by file to typed alerts.
5. **Extract the self-contained extensions into models.** In order: `ConflictVersionTracker`, `VaultAppearanceModel` (with the theme), `BookmarksModel`, `GraphAndMapCache`, `FileRecoveryModel`. Each already has its state grouped (section 3.1, rows 14–18).
6. **Extract `VaultSearch` and `VaultIndexing`.** `startIndexing` and `refreshIndex` callers keep calling through the workspace until step 9.
7. **Extract the write workflows** (`NoteCreation`, `AttachmentPublisher`, `DrawingWorkflow`, `RecordingWorkflow`) with one `afterWrite(paths:)` hook.
8. **Extract `TabWorkspace`.** Add the `DocumentOpener` registry, and make `TabDocument` hold one `DocumentSession`. Make the switches over `DocumentKind` exhaustive (OCP-SHELL-01).
9. **Introduce `OpenVault` and the `VaultScoped` protocol.** Replace the field-by-field reset in `openVault` with "build, then install" (SRP-SHELL-02).
10. **One command catalogue** for the palette and the menu bar, a `CreationCatalogue`, and `SidebarPanel` descriptors (OCP-SHELL-02, -03, -05).
11. **Narrow the views' inputs** (ISP-SHELL-01), starting with the leaf views: `TabSwitcher`, `SearchResultRow`, `VaultItemDragPreview`, `ConflictVersionsBanner`, the settings pages.
12. **Split `GraphiteRootView`** (section 3.2) and `VaultSidebar` (section 3.3). Fix BUG-SHELL-04 by making reveal an intent on `VaultFileList` that the root observes to show the sidebar.
13. **`PluginWorkspaceAccess`** replaces the host's back-reference.

### Behaviour that must be preserved

| ID | Invariant | Test idea |
| --- | --- | --- |
| SHELL-INV-01 | Per-vault preference keys are `"GraphiteExpandedFolders." + UUID.uuidString`, `"GraphiteRecentFiles." + …`, `"GraphiteTabLayout." + …`, `"GraphiteDocumentPlaces." + …` and `"GraphiteFolds." + …` ([WorkspaceModel.swift:28](../../../Sources/GraphiteUI/WorkspaceModel.swift#L28), [88](../../../Sources/GraphiteUI/WorkspaceModel.swift#L88); [WorkspaceTabs.swift:86](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L86); [WorkspacePlaces.swift:9](../../../Sources/GraphiteUI/WorkspacePlaces.swift#L9); [WorkspaceFolds.swift:8](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L8)). Value formats: a sorted string array; a string array, most recent first; JSON `SavedTabLayout`; JSON `DocumentPlaceMemory`; `[String: [String]]` from a note path to sorted fold keys. | Golden test: write values with the old code's formats into a defaults suite and read them through `VaultDeviceMemory`. |
| SHELL-INV-02 | The vault list lives under `"GraphiteKnownVaults"` as JSON with a `"vaults"` array. Undecodable entries are written back unchanged. A list that cannot be decoded at all is kept under `"GraphiteKnownVaults.unreadable"`. The legacy `"GraphiteVaultBookmark"` is removed only after it resolves, and is dated before the oldest vault ([VaultLibrary.swift:12-16](../../../Sources/GraphiteUI/VaultLibrary.swift#L12-L16), [67-131](../../../Sources/GraphiteUI/VaultLibrary.swift#L67-L131)). | The existing [UiFileManagementFixTests.swift:276-336](../../../Tests/GraphiteUITests/UiFileManagementFixTests.swift#L276-L336), renamed `VaultLibraryTests`. |
| SHELL-INV-03 | The `GraphitePreferences` key strings ([GraphitePreferences.swift:155-188](../../../Sources/GraphiteUI/GraphitePreferences.swift#L155-L188)), their defaults and their validation ranges: snapshot interval 1...60 (default 5), history 1...365 (default 7), legacy text size 12...28, notebook spacing within `NotebookPaperSpacing.choices`, transparent notebook paper read as white ([357-397](../../../Sources/GraphiteUI/GraphitePreferences.swift#L357-L397)). | Table test: each key with an absent value, a valid value and an invalid value gives the documented default. |
| SHELL-INV-04 | Device UI keys: `"sidebarPanel"`, `"tagsViewSortOrder"`, `"tagsViewShowsNestedTags"`, `"propertiesViewSortOrder"` ([VaultSidebarPanels.swift:87-92](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L87-L92)); `"GraphiteReadAloudFloatingPlayer"`; `"GraphiteInspectorPanel"`; `"GraphiteRecentCommands"`. The latter stores palette command identifiers, so these identifiers are persisted: `"switcher"`, `"new-note"` … ([WorkspaceCommands.swift:26-252](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L26-L252)) and the prefixes `"community-plugin:"`, `"community-plugin-ribbon:"` and `"community-plugin-view:"` ([153-161](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L153-L161)). | Snapshot test of the catalogue's identifier set; a stored recent list survives the catalogue refactor. |
| SHELL-INV-05 | Drag types `com.graphite.study.tab` and `com.graphite.study.vault-item` match Info.plist. `VaultItemTransfer` encodes as JSON `{"path": …}`, and the Mac tree uses the same bytes ([WorkspacePanes.swift:7-17](../../../Sources/GraphiteUI/WorkspacePanes.swift#L7-L17), [VaultSidebar.swift:37-47](../../../Sources/GraphiteUI/VaultSidebar.swift#L37-L47), [MacFileTree.swift:386-391](../../../Sources/GraphiteUI/MacFileTree.swift#L386-L391)). | Encode, then decode, a `VaultItemTransfer` through both the SwiftUI and the AppKit paths. |
| SHELL-INV-06 | A recording's file name is `"<focused file stem, or the vault name> Recording yyyy-MM-dd HH-mm"` in the Gregorian calendar and 24-hour time, `.m4a` or `.mp4`, placed in the note's attachment folder or the current folder ([WorkspaceModel.swift:1118-1121](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1118-L1121), [1139-1142](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1139-L1142), [1174-1177](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1174-L1177)). | The existing timestamp test, plus a destination test through `RecordingWorkflow` with an injected clock. |
| SHELL-INV-07 | A pasted image's stem is `"Pasted image yyyyMMddHHmmss"`. A name taken between choosing and writing is retried up to 20 times, numbered `Name 1`, `Name 2` ([WorkspaceModel.swift:916-940](../../../Sources/GraphiteUI/WorkspaceModel.swift#L916-L940)). | The existing [UiWorkspaceModelFixTests.swift:325-342](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L325-L342). |
| SHELL-INV-08 | New files: a note is empty ([WorkspaceModel.swift:719](../../../Sources/GraphiteUI/WorkspaceModel.swift#L719)). A base is exactly `"views:\n  - type: table\n    name: Table\n"` ([786](../../../Sources/GraphiteUI/WorkspaceModel.swift#L786)). A canvas is `CanvasFile.emptyFileData` ([WorkspaceCanvas.swift:29](../../../Sources/GraphiteUI/WorkspaceCanvas.swift#L29)). All are written with `.absent` under a unique name, in the requested folder or the vault's new-note location. A new note opens ready to type ([WorkspaceModel.swift:723](../../../Sources/GraphiteUI/WorkspaceModel.swift#L723)). | Golden bytes per kind through `NoteCreation`. |
| SHELL-INV-09 | Vault switch order, all in [WorkspaceModel.swift:261-346](../../../Sources/GraphiteUI/WorkspaceModel.swift#L261-L346):<br>1. refuse while recording;<br>2. remember places;<br>3. save, where a failure keeps the current vault;<br>4. obtain access;<br>5. read settings, the root and the index;<br>6. save again and flush appearance;<br>7. plugins `vaultWillClose`;<br>8. `saveAllChanges`;<br>9. stop monitor, indexing and external refresh;<br>10. `layoutVaultIdentifier = nil`, then reset the layout and tabs;<br>11. set `currentVaultIdentifier`, then load expanded folders and recent files;<br>12. reload settings;<br>13. start indexing;<br>14. restore the layout;<br>15. check recordings;<br>16. plugins `vaultDidOpen`;<br>17. open the daily note if set. | Spy `VaultScoped` conformers record call order; a failing save leaves the old `OpenVault` installed ([UiWorkspaceModelFixTests.swift:115-149](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L115-L149)). |
| SHELL-INV-10 | Unreadable vault settings fall back to Obsidian's defaults, never to the previous vault's ([WorkspaceModel.swift:282-284](../../../Sources/GraphiteUI/WorkspaceModel.swift#L282-L284), [324-326](../../../Sources/GraphiteUI/WorkspaceModel.swift#L324-L326)). | The existing [UiWorkspaceModelFixTests.swift:96-109](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L96-L109). |
| SHELL-INV-11 | `selection`, `history`, `activeTabID` and `openTabCount` follow `layout` and change only when their value changes. The layout is persisted only when `layout.saved` changes ([WorkspaceModel.swift:40-52](../../../Sources/GraphiteUI/WorkspaceModel.swift#L40-L52)). | The existing observation-tracking tests ([UiWorkspaceModelFixTests.swift:527-550](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L527-L550); `UiWorkspaceAreaHandoffTests` lines 656 and 683). |
| SHELL-INV-12 | A file is open in at most one tab. Paths are normalised to the file system's spelling (`storedPath`) before lookup. A file a plugin shows opens in that plugin's view ([WorkspaceModel.swift:428-482](../../../Sources/GraphiteUI/WorkspaceModel.swift#L428-L482), [1301-1306](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1301-L1306)). | Open `note.md` and `Note.md` on a case-insensitive volume: one tab. |
| SHELL-INV-13 | A tab closes only after its documents saved, retrying while the person types. "Close others" closes only the tabs it saved. Closing a side saves tabs opened meanwhile ([WorkspaceTabs.swift:177-239](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L177-L239)). | A failing save keeps the tab open and raises an alert; a tab added during the save stays open. |
| SHELL-INV-14 | Loading into a tab follows these rules ([WorkspaceTabs.swift:329-415](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L329-L415)):<br>• the latest request wins;<br>• the old session saves all changes before the swap;<br>• a path opened meanwhile in another tab is activated there instead;<br>• a password failure keeps the requested page;<br>• a restored tab's failure shows in the tab, not as an alert. | Two overlapping loads: only the second's session is installed. |
| SHELL-INV-15 | Hidden tabs keep at most 1 PDF session. A session with unsaved edits, a save in progress, a conflict, or still opening is never released. A released PDF reopens on the same page ([WorkspaceTabs.swift:251-271](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L251-L271)). | The existing [UiSidebarPaletteFixTests.swift:152-179](../../../Tests/GraphiteUITests/UiSidebarPaletteFixTests.swift#L152-L179). |
| SHELL-INV-16 | External changes:<br>• a refresh runs 500 ms after the last report, and at most 2 s after the first;<br>• more than 200 paths, a folder, a path outside the vault, or the root alone triggers a whole-vault scan;<br>• paths with a hidden component are ignored;<br>• results for a vault that is no longer open are dropped ([WorkspaceModel.swift:1226-1283](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1226-L1283), [1405-1453](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1405-L1453)). | The existing pure tests ([UiWorkspaceModelFixTests.swift:237-258](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L237-L258), [493-504](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L493-L504)), plus a coordinator test with an injected clock. |
| SHELL-INV-17 | Indexing ([WorkspaceModel.swift:516-577](../../../Sources/GraphiteUI/WorkspaceModel.swift#L516-L577)):<br>• a scan requested during a scan runs once afterwards;<br>• a stopped or replaced run reports nothing;<br>• `hasCompletedIndexScan` is false while a rebuild empties the index;<br>• the scan runs at `.utility` priority. | The existing [UiWorkspaceModelFixTests.swift:220-233](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L220-L233), [435-446](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L435-L446). |
| SHELL-INV-18 | Following an unresolved link ([WorkspaceModel.swift:652-707](../../../Sources/GraphiteUI/WorkspaceModel.swift#L652-L707), [737-776](../../../Sources/GraphiteUI/WorkspaceModel.swift#L737-L776)):<br>• it creates a note only after a complete index scan;<br>• a link naming an attachment kind creates nothing;<br>• `[[Folder]]` next to a folder of that name names a note;<br>• `[[Homework 2.1]]` creates `Homework 2.1.md`;<br>• a backslash in the folder part is refused;<br>• `#page=N` opens a PDF page, `#View` opens a base view, `#^id` shows a block. | The existing [UiWorkspaceModelFixTests.swift:174-214](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L174-L214) and [UiWorkspaceAreaHandoffTests.swift:273](../../../Tests/GraphiteUITests/UiWorkspaceAreaHandoffTests.swift#L273). |
| SHELL-INV-19 | Links written for files ([WorkspaceModel.swift:943-992](../../../Sources/GraphiteUI/WorkspaceModel.swift#L943-L992)):<br>• a "shortest" link uses the bare name only after a complete scan proves the name unique;<br>• names containing `|[]#^` get a Markdown link percent-encoded with the RFC 3986 unreserved set;<br>• images, media and PDFs get an embed. | The existing [UiWorkspaceModelFixTests.swift:406-429](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L406-L429). |
| SHELL-INV-20 | An insertion chosen in older text moves with text typed before it. Text typed after it leaves it in place. If its own characters changed, it goes to the cursor and replaces nothing ([WorkspaceModel.swift:893-912](../../../Sources/GraphiteUI/WorkspaceModel.swift#L893-L912)). | The existing pure tests ([UiWorkspaceModelFixTests.swift:346-383](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L346-L383)). |
| SHELL-INV-21 | An attachment or drawing file is always kept. Its embed is not inserted when the note closed or is in conflict, and an alert names the file ([WorkspaceModel.swift:875-891](../../../Sources/GraphiteUI/WorkspaceModel.swift#L875-L891), [1052-1066](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1052-L1066)). | The existing [UiWorkspaceModelFixTests.swift:386-400](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L386-L400). |
| SHELL-INV-22 | Moves ([WorkspaceFileManagement.swift:84-228](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L84-L228)):<br>• refused before the first complete scan, and when the destination is taken by another item (a change of capitals alone is allowed);<br>• one link question at a time, later moves queued in order;<br>• edited notes are saved and re-indexed before planning;<br>• text typed during the move is written at the new path if the revision matches, else to `"<stem> Graphite edits.md"`. | The existing `UiFileManagementFixTests` lines 29-178 and [UiWorkspaceAreaHandoffTests.swift:322-351](../../../Tests/GraphiteUITests/UiWorkspaceAreaHandoffTests.swift#L322-L351). |
| SHELL-INV-23 | Deletion ([WorkspaceFileManagement.swift:259-283](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L259-L283), [WorkspaceRecovery.swift:28-39](../../../Sources/GraphiteUI/WorkspaceRecovery.swift#L28-L39)):<br>• confirm when the vault's setting asks for it;<br>• save, then snapshot up to 500 notes, then delete with the vault's method;<br>• tabs close only after success;<br>• a notice when the system trash fell back to `.trash`. | The existing [UiFileManagementFixTests.swift:99-133](../../../Tests/GraphiteUITests/UiFileManagementFixTests.swift#L99-L133). |
| SHELL-INV-24 | Conflict checks ([WorkspaceConflictVersions.swift:25-192](../../../Sources/GraphiteUI/WorkspaceConflictVersions.swift#L25-L192)):<br>• only files the sidebar lists or a tab shows;<br>• at most 5,000 waiting, oldest dropped, batches of 100;<br>• cancelled on vault switch;<br>• a replacement is refused when the file's stamp changed since listing;<br>• no version is removed unless chosen. | The existing [WorkspaceConflictVersionsTests.swift](../../../Tests/GraphiteUITests/WorkspaceConflictVersionsTests.swift). |
| SHELL-INV-25 | When the scene leaves `.active`, document places are remembered synchronously before any save task. Returning to `.active` re-checks open documents, the root listing and vault settings ([GraphiteRootView.swift:227-238](../../../Sources/GraphiteUI/GraphiteRootView.swift#L227-L238)). | A `SceneLifecycleSaver` unit test with a fake clock asserts the order: places, then save. |
| SHELL-INV-26 | Deep links ([GraphiteRootView.swift:203-226](../../../Sources/GraphiteUI/GraphiteRootView.swift#L203-L226), [WorkspaceDeepLinks.swift:6-117](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L6-L117)):<br>• queued until the last vault has reopened, then handled in arrival order;<br>• a vault is named by identifier, then exact name, then case-insensitive name;<br>• `open?path=` accepts absolute paths inside any known vault;<br>• `file=` never creates a note;<br>• `new` writes through the editor when the note is open. | The existing deep-link test ([UiWorkspaceModelFixTests.swift:80-92](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L80-L92)), plus a queue test on `DeepLinkInbox`. |
| SHELL-INV-27 | Mac:<br>• a single `Window` with identifier `"main"` and a `Settings` scene on the same workspace;<br>• quitting waits at most 5 s for saves and answers the application exactly once;<br>• ⌘W in Settings closes the Settings window ([GraphiteMacScenes.swift:22-77](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L22-L77), [SettingsView.swift:79-84](../../../Sources/GraphiteUI/SettingsView.swift#L79-L84)). | `TerminationReply` answers once when both tasks finish. A failed save does not quit silently (after the BUG-SHELL-03 fix). |
| SHELL-INV-28 | Vault settings changes from Settings are written one after another, each applied to the previous result. Only changed keys of `app.json` are written. A rejected attachment folder leaves the saved value and raises an alert ([SettingsView.swift:960-986](../../../Sources/GraphiteUI/SettingsView.swift#L960-L986), [WorkspaceModel.swift:394-414](../../../Sources/GraphiteUI/WorkspaceModel.swift#L394-L414)). | The existing [UiRootSettingsTests.swift:221-266](../../../Tests/GraphiteUITests/UiRootSettingsTests.swift#L221-L266) and [UiWorkspaceAreaHandoffTests.swift:302](../../../Tests/GraphiteUITests/UiWorkspaceAreaHandoffTests.swift#L302). |
| SHELL-INV-29 | Search ([WorkspaceModel.swift:598-636](../../../Sources/GraphiteUI/WorkspaceModel.swift#L598-L636), [VaultSidebar.swift:168-173](../../../Sources/GraphiteUI/VaultSidebar.swift#L168-L173)):<br>• an invalid `/regex/` is explained and not searched;<br>• results for an older query or sort are ignored;<br>• the next page drops paths already shown;<br>• cancellation is silent;<br>• an empty query clears the results;<br>• there is a 180 ms debounce. | The existing [UiWorkspaceAreaHandoffTests.swift:244-262](../../../Tests/GraphiteUITests/UiWorkspaceAreaHandoffTests.swift#L244-L262). |
| SHELL-INV-30 | Accent precedence: the accent chosen on the device, then the vault's Obsidian accent, then the default. Choosing an accent never writes the vault's file ([GraphitePreferences.swift:277-288](../../../Sources/GraphiteUI/GraphitePreferences.swift#L277-L288)). | A table test over the three sources. |
| SHELL-INV-31 | Removing a vault never touches its folder. It deletes its recovery copies, index, plugin consent and every per-vault device key. The open vault cannot be removed ([WorkspaceModel.swift:244-258](../../../Sources/GraphiteUI/WorkspaceModel.swift#L244-L258)). | Extend [UiWorkspaceModelFixTests.swift:152-169](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L152-L169) to every registered key, folds included. |
| SHELL-INV-32 | Quick switcher ([QuickPalette.swift:243-273](../../../Sources/GraphiteUI/QuickPalette.swift#L243-L273)):<br>• empty, it lists up to 20 existing recent files, excluding the open one;<br>• the 10 most recent paths get a +1.5 rank bonus;<br>• "Create" is offered only for a valid note name that does not already exist, and needs an explicit choice until the index is complete. | Pure test of the item builder, once it takes values. |

### Tests that become possible once the seams exist
- **`VaultSwitcher` order test:** spy `VaultScoped` models record `vaultWillClose` and `vaultDidOpen` order, with no real vault folder (SHELL-INV-09).
- **`VaultDeviceMemory` round-trip and `forgetVault` completeness:** a test fails if a registered family is not removed (SHELL-INV-01, SHELL-INV-31).
- **`ExternalChangeCoordinator` with an injected clock:** debounce and maximum delay, without sleeping (SHELL-INV-16).
- **`DocumentOpener` registry exhaustiveness:** every `DocumentKind` case has a handler, and each handler's session round-trips save and unsaved state.
- **`WorkspaceCommandCatalogue` parity:** every menu-bar command and every palette command comes from the catalogue. Shortcut labels equal their `KeyboardShortcut`. Identifiers are stable (SHELL-INV-04).
- **`SceneLifecycleSaver`:** on the Mac and the iPad, a failed save produces a typed alert or a separate copy, never silent termination (BUG-SHELL-03).
- **Leaf views built from value inputs:** `TabSwitcher`, `SearchResultRow` and `ConflictVersionsBanner` in hosted snapshot tests without a vault.
- **Plugin host tests with a fake `PluginWorkspaceAccess`:** `workspace.renameFile` waits for the link question without a real workspace.
- **Typed-alert tests** that assert on `WorkspaceAlert` cases instead of sentences (CC-SHELL-09).

## 8. Appendix: raw metrics

### Reconnaissance figures (method: Python script; code lines exclude blank lines, comment-only lines and string contents)

**Functions over 40 code lines (29):**

| Function | Code lines | Location |
| --- | ---: | --- |
| `GraphiteRootView.body` | 172 | GraphiteRootView.swift:62 |
| `WorkspaceCommandList.commands` | 120 | WorkspaceCommands.swift:24 |
| `DrawingsSettingsPage.body` | 102 | SettingsView.swift:474 |
| `VaultSidebar.body` | 84 | VaultSidebar.swift:121 |
| `WorkspaceModel.load` | 77 | WorkspaceTabs.swift:329 |
| `QuickPalette.body` | 73 | QuickPalette.swift:50 |
| `ColorsSettingsPage.body` | 66 | SettingsView.swift:378 |
| `TabBar.body` | 64 | WorkspacePanes.swift:173 |
| `AppIconSettingsSection.body` | 63 | AppIconSettingsSection.swift:25 |
| `WorkspaceModel.openVault` | 62 | WorkspaceModel.swift:267 |
| `SettingsView.body` | 61 | SettingsView.swift:24 |
| `CreateDocumentSheet.body` | 59 | GraphiteRootView.swift:659 |
| `EmptyTabView.body` | 58 | WorkspacePanes.swift:666 |
| `EditorSettingsPage.body` | 56 | SettingsView.swift:187 |
| `TabSwitcher.row` | 54 | TabSwitcher.swift:47 |
| `FontFamilyPickerPage.body` | 52 | FontSettings.swift:178 |
| `WorkspaceModel.open` | 49 | WorkspaceModel.swift:428 |
| `TabItem.body` | 48 | WorkspacePanes.swift:330 |
| `GraphiteCommands.viewCommands` | 48 | GraphiteCommands.swift:90 |
| `TabDocumentView.loadedContent` | 47 | WorkspacePanes.swift:508 |
| `WorkspaceModel.handle` | 47 | WorkspaceDeepLinks.swift:6 |
| `NewVaultForm.body` | 47 | VaultSwitcher.swift:263 |
| `GeneralSettingsPage.body` | 46 | SettingsView.swift:125 |
| `WorkspaceCommandList.noteCommands` | 43 | WorkspaceCommands.swift:210 |
| `FileManagementPresentation.body` | 43 | VaultSidebar.swift:930 |
| `WorkspaceCommandList.tabCommands` | 42 | WorkspaceCommands.swift:167 |
| `FileRecoverySheet.body` | 42 | FileRecoverySheet.swift:22 |
| `VaultSidebar.searchResults` | 41 | VaultSidebar.swift:392 |
| `GraphitePreferences.init` | 41 | GraphitePreferences.swift:357 |

**Types (single declaration blocks) over 300 code lines:**
- `WorkspaceModel` 995 (WorkspaceModel.swift:8);
- `GraphiteRootView` 475 (GraphiteRootView.swift:7);
- `VaultSidebar` 329 (VaultSidebar.swift:51).

**Files over 400 code lines:**
- `WorkspaceModel.swift` 1,050;
- `VaultSidebar.swift` 952;
- `SettingsView.swift` 950;
- `WorkspacePanes.swift` 687;
- `GraphiteRootView.swift` 623;
- `ConflictVersionsSheet.swift` 406.

**Commits touching each file** (git log over all 242 commits up to b13dec3, top 15):

| File | Commits |
| --- | ---: |
| `WorkspaceModel.swift` | 29 |
| `GraphiteRootView.swift` | 28 |
| `VaultSidebar.swift` | 24 |
| `WorkspacePanes.swift` | 22 |
| `SettingsView.swift` | 21 |
| `GraphitePreferences.swift` | 14 |
| `WorkspaceTabs.swift` | 11 |
| `VaultSwitcher.swift` | 7 |
| `WorkspaceCommands.swift` | 6 |
| `GraphiteApp.swift` | 6 |
| `VaultSidebarPanels.swift` | 5 |
| `GraphiteCommands.swift` | 5 |
| `WorkspaceFileManagement.swift` | 4 |
| `WorkspaceDeepLinks.swift` | 4 |
| `QuickPalette.swift` | 4 |

### Pattern counts, reconnaissance versus this audit

| Pattern | Reconnaissance | This audit | How checked |
| --- | ---: | ---: | --- |
| `try?` | 95 | not recounted | 11 user-relevant sites listed in CC-SHELL-04 |
| `Task.sleep` / sleep | 9 | 9 | Read: GraphiteRootView.swift:472; WorkspacePanes.swift:822; VaultSidebar.swift:130, 172, 1021; QuickPalette.swift:232; WorkspaceDeepLinks.swift:83; WorkspaceModel.swift:1234; GraphiteMacScenes.swift:59 |
| `.shared` | 16 | 16 | Read: DrawingEditorDraftStore 4, UIApplication 10, DocumentPlaceStore 1, EmbeddedPDFSessions 1 |
| `static var` | 12 | 12, of which 3 are mutable stored | The rest are computed. Mutable: GraphiteRootView.swift:565, GraphitePreferences.swift:308, GraphiteMacScenes.swift:46 |
| `MainActor.assumeIsolated` | 2 | 2 | GraphiteRootView.swift:597, PresentedScreenObserver.swift:62 |
| `Date()` / `Date.now` | 1 | 1 `Date()` | WorkspacePlaces.swift:32; `.now` defaults and `ContinuousClock.now` listed in DIP-SHELL-05 |
| `UserDefaults` | 22 | — | 12 direct `UserDefaults.standard` calls in the `Workspace*.swift` files (grep), plus `@AppStorage` and the injected `defaults` uses |
| `FileManager.default` | 11 | — | Not recounted |
| `default:` in switch | 6 | 6 | WorkspaceTabs.swift:376, WorkspacePanes.swift:553, ConflictVersionsSheet.swift:354 (all over `DocumentKind`); WorkspaceBookmarks.swift:76, VaultSidebarPanels.swift:401, 434 (bookmark type strings) |
| `[String: Any]` | 2 | 2 | VaultLibrary.swift:70, 101 |
| `Task { }` | 155 | not recounted | — |
| `DispatchQueue.main` | 2 | 2 | MacFileTree.swift:44, PresentedScreenObserver.swift:81 |
| `fatalError` | 1 | 1 | MacFileTree.swift:469, the unavailable `init(coder:)` |

### Counts made for this audit

| Measure | Value | Method |
| --- | ---: | --- |
| `WorkspaceModel` stored properties | 86 | Counted by reading WorkspaceModel.swift:12-209, 1011, 1097-1105, 1277 |
| `WorkspaceModel` functions in the main file | 74 | grep `^\s*(@discardableResult\s+)?((private\|fileprivate\|static\|nonisolated)\s+)*func \w+` |
| Files containing `extension WorkspaceModel` | 23 (24 blocks) | grep `extension WorkspaceModel` over `**/*.swift` |
| `WorkspaceTabs.swift` extension members | 30 functions + 2 computed properties | Counted by reading lines 84-444 |
| `GraphitePreferences` stored properties | 36 | Counted by reading lines 207-355 |
| `GraphitePreferences` persisted keys | 34 | Counted by reading the `Key` enum, lines 155-188 |
| `GraphiteRootView` state properties | 16 + 3 environment values + 1 static | Counted by reading lines 8-39 and 565 |
| `GraphiteRootView` presentations in `body` | 12, plus 2 presentation modifiers | Counted by reading lines 106-250 |
| `VaultSidebar` properties | 16 | Counted by reading lines 52-71 |
| Fields reset by hand in `openVault` | 33 | Counted by reading WorkspaceModel.swift:303-337 |
| Assignments to `errorMessage` in `Workspace*.swift` | 82 | grep `errorMessage = ` (84 matches minus 2 that set `pdfSession.errorMessage`) |
| View declarations taking `WorkspaceModel` | 70 in the UI module, 51 in scope | grep `(var\|let) workspace: WorkspaceModel` |
| `CommunityPluginHost` uses of workspace members | about 23 distinct members | grep `workspace\??\.[a-zA-Z]+` over `CommunityPlugin*.swift` |
| UI files touched by the canvas kind | 13, plus `DocumentKind` in Core | grep `\.canvas\b\|canvasSession\|createCanvas\|CanvasSession`, minus the canvas feature's own files and unrelated `canvas` properties |
| Commands declared in both palette and menu bar | 27 | GraphiteCommands.swift:61-177 compared by reading with WorkspaceCommands.swift:24-252 |
| Lists of creatable kinds | 7 | Counted by reading (OCP-SHELL-05) |
| Branch sites per new sidebar panel | 7 in 4 files | Counted by reading (OCP-SHELL-03) |
| Files and sites per new device setting | 2 files, 4 sites: `Key` constant, stored property with `didSet`, initializer line, settings row | Counted by reading GraphitePreferences.swift and SettingsView.swift |
| Duplicated logic pairs | 11 | Counted by reading (CC-SHELL-05) |
| Incident or date comments | 9 | Counted by reading (CC-SHELL-08) |
| String-literal preference keys used in more than one file | 2: `"GraphiteInspectorPanel"` (3 uses), `"GraphiteReadAloudFloatingPlayer"` (2 uses) | grep |

### Not read
- `Docs/Coverage.md` beyond the lines that grep `WorkspaceModel|GraphiteRootView|…` returned.
- The test files `UiWorkspaceAreaHandoffTests.swift`, `UiSidebarPaletteFixTests.swift` and `UiFileManagementFixTests.swift` were read through their test names and the line ranges cited above, not in full.
- `FileRecoveryStore`, `VaultStore`, `TabLayout` and `CommunityPluginHost` were read only at the lines cited, since they belong to other areas.

### Corrections to figures earlier in this document (recounted while checking; these figures replace the earlier ones)

| Where | Earlier figure | Correct figure | Recount |
| --- | --- | --- | --- |
| SRP-SHELL-02, CC-SHELL-01, section 8 ("fields reset by hand in `openVault`") | 33 | **31 field assignments**, plus 9 reset calls | Read WorkspaceModel.swift:303-337. Assignments: `pendingExternalChanges`, `firstPendingExternalChangeInstant`, `indexingMessage`, `folderAccess`, `store`, `index`, `monitor`, `readAloud.vaultRoot`, `layoutVaultIdentifier`, `layout`, `tabDocuments`, `pdfPasswords`, `restorableSidebarPluginViews`, `pickedSidebarFiles`, `graphCache`, `graphPositions`, `placedNotesCache`, `embeddedBaseModelCache`, `pendingMove`, `pendingDeletion`, `fileSheet`, `searchQuery`, `searchResults`, `searchContinuation`, `rootEntries`, `hasCompletedIndexScan`, `vaultSettings`, `currentVaultIdentifier`, `expandedFolders`, `recentFiles`, `fileRecovery`. |
| SRP-SHELL-02, list of fields not reset | included `recordingRecoveryOffer` | **Remove `recordingRecoveryOffer`** from that list | `checkForUnfinishedRecordings()` at WorkspaceModel.swift:343 reassigns it ([WorkspaceRecordingRecovery.swift:16-19](../../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L16-L19)). The other eight fields listed stay correct. |
| Section 8, `UserDefaults` row | 12 direct calls in `Workspace*.swift` | **14** | WorkspaceModel.swift 5 (23, 83, 255, 332, 334); WorkspaceTabs.swift 2 (421, 432); WorkspaceFolds.swift 2 (14, 18); WorkspaceCommands.swift 3 (71, 82, 89); WorkspaceFileManagement.swift 1 (288); WorkspaceBookmarks.swift 1 (83); from grep `UserDefaults\.standard` |
| Section 3.3 and CC-SHELL-10, types in `VaultSidebar.swift` | "19 more types" / 20 | **22 top-level types** (21 besides `VaultSidebar`) | Counted by reading: `CreationRequest`, `CreationKind`, `VaultItemTransfer`, `VaultSidebar`, `FileExplorerMenuItems`, `SearchOperatorSuggestion`, `SearchResultRow`, `FileTreeContents`, `FileTreeRow`, `FileTreeRows`, `VaultEntryRow`, `VaultEntryMenu`, `VaultItemDragPreview`, `FileTreeRowLabel`, `SidebarListStyle`, `FileTreeMetrics`, `FileSheet`, `FileManagementPresentation`, `RenameSheet`, `RenamedFileName`, `NewFolderSheet`, `MoveSheet` |
| CC-SHELL-10, types in `WorkspacePanes.swift` | 14 | **13 top-level types** | `TabTransfer`, `WorkspacePanes`, `TabGroupPane`, `TabBar`, `TabItem`, `QuietIconButtonStyle`, `SplitDivider`, `TabDocumentView`, `Pasteboard`, `PDFPasswordPrompt`, `EmptyTabView`, `WindowTouchObserver`, `DelayedProgressView` |
| Section 3.3, `VaultSidebar` property split | 4 inputs, 9 state or storage, 3 environment | **5 inputs, 8 state or storage, 3 environment** (total 16 unchanged) | Inputs: `workspace`, `creation`, `showsSettings`, `showsVaultManager`, `showDocument` (VaultSidebar.swift:52-58) |

## 9. Since the snapshot

Delta audit of 2026-10-19 against `FR-01` to `FR-108`, in two parts: the notebook library at `9040705` (commits `7f56e00`, `2e1b6a2`, `e9ce084`), and the other shell changes at `fff794b`.

### The notebook library (9040705)

The library keeps the storage contracts: a notebook is an ordinary PDF ([WorkspaceNotebookInsertion.swift:37](../../../Sources/GraphiteUI/WorkspaceNotebookInsertion.swift#L37)), folder colours live in an optional `.obsidian/graphite-folder-styles.json` created only once a style exists ([VaultStoreFolderStyles.swift:12-27](../../../Sources/GraphiteCore/VaultStoreFolderStyles.swift#L12-L27)), and previews live in memory only. `LibraryView` takes values and closures, not the workspace. The findings below are in its error handling, task ownership, memory budget and duplication.

#### BUG-SHELL-07 A damaged `.obsidian/graphite-folder-styles.json` makes every folder of the library show "Can't Show This Folder"
- **Severity:** High (verdict: Confirmed, traced by the lead)
- **Rule:** `FR-59`, `FR-61`
- **Evidence:** traced path, introduced in `2e1b6a2` on top of `7f56e00`:
  1. The style file is not JSON, or valid JSON of the wrong shape (for example `"folders": []`).
  2. Every listing reads the styles in the same `do` block as the folder's entries ([LibraryModel.swift:77-78](../../../Sources/GraphiteUI/LibraryModel.swift#L77-L78)); decoding throws ([FolderStyleList.swift:100-114](../../../Sources/GraphiteCore/FolderStyleList.swift#L100-L114)).
  3. The catch sets `failure = .folderUnreadable`: at the root the path is empty, and in a subfolder `fileExists` is true, so both land there ([LibraryModel.swift:84-92](../../../Sources/GraphiteUI/LibraryModel.swift#L84-L92)).
  4. The view shows "Can't Show This Folder" with a message that blames the folder ([LibraryView.swift:143-145](../../../Sources/GraphiteUI/LibraryView.swift#L143-L145), [:164-165](../../../Sources/GraphiteUI/LibraryView.swift#L164-L165)); `setStyle` fails the same way. The only remedy is deleting a hidden file by hand.
- **Why it matters:** an optional cosmetic file takes down the file browser in Library mode, which is the iPad window's home and replaces the iPhone's file list.
- **Fix direction:** read the styles apart from the listing; an unreadable style file means plain folders plus a typed notice, and the file is moved aside (`CC-VAULT-12`).

#### BUG-SHELL-08 A file that changes while its tile is on screen keeps its old preview
- **Severity:** Medium (verdict: Confirmed by trace)
- **Rule:** `FR-13`
- **Evidence:** a change bumps `directoryVersion` and so `reloadKey` ([LibraryView.swift:17-19](../../../Sources/GraphiteUI/LibraryView.swift#L17-L19)); `listFolder` replaces `items` but leaves `visiblePreviews` and `previewTasks` ([LibraryModel.swift:80-83](../../../Sources/GraphiteUI/LibraryModel.swift#L80-L83)); `VaultEntry.id` is the path, so `onAppear` does not fire again ([LibraryView.swift:156](../../../Sources/GraphiteUI/LibraryView.swift#L156)); only `tileAppeared` starts a versioned preview ([LibraryModel.swift:118-137](../../../Sources/GraphiteUI/LibraryModel.swift#L118-L137)). Introduced in `2e1b6a2`.
- **Why it matters:** `Docs/Notebook-library-and-new-file-todo.md` marks "Previews follow changes" done; for a visible tile it is false.
- **Fix direction:** after a listing, restart the previews of visible paths whose cache key changed; key `visiblePreviews` by `LibraryPreviewCache.Key`.

#### BUG-SHELL-09 A tile's preview keeps rendering after the tile scrolls away, with no limit on concurrent renders
- **Severity:** Medium (verdict: Confirmed for the cancellation; the effect on on-screen previews is Plausible and needs a measurement on a large vault)
- **Rule:** `FR-66`, `FR-103`, `FR-104`, `FR-80`
- **Evidence:** each tile starts an owned `Task` that awaits a `Task.detached` render ([LibraryModel.swift:130-131](../../../Sources/GraphiteUI/LibraryModel.swift#L130-L131)); `tileDisappeared` cancels only the outer task ([:145](../../../Sources/GraphiteUI/LibraryModel.swift#L145)), which a detached task does not inherit; the loader never checks for cancellation and renders inside a synchronous `NSFileCoordinator.coordinate` ([LibraryPreviewLoader.swift:39-48](../../../Sources/GraphiteApple/LibraryPreviewLoader.swift#L39-L48), [:70-83](../../../Sources/GraphiteApple/LibraryPreviewLoader.swift#L70-L83)). The doc comment "Stops a tile's preview work" ([LibraryModel.swift:139](../../../Sources/GraphiteUI/LibraryModel.swift#L139)) contradicts the code; the same pattern is at [NotebookPaperPictures.swift:54-56](../../../Sources/GraphiteUI/NotebookPaperPictures.swift#L54-L56). Introduced in `2e1b6a2`.
- **Why it matters:** a fast scroll over hundreds of PDFs renders every tile it passed, each blocking a cooperative-pool thread, so on-screen previews wait behind invisible work; the plan's "cancelled when scrolled away" does not hold.
- **Fix direction:** run the load as a child task, check cancellation between read and render, and share a limit of about four renders at once (as P-16 does for thumbnails).

#### CC-SHELL-11 The preview cache is bounded by count only, with no byte budget and no release on a vault switch
- **Severity:** Medium
- **Rule:** `FR-72`, `FR-105`
- **Evidence:** `cachedPreviewCount = 240` and `previewPixels = 540` ([LibraryModel.swift:19-21](../../../Sources/GraphiteUI/LibraryModel.swift#L19-L21)); the `NSCache` has only a `countLimit` ([:187-199](../../../Sources/GraphiteUI/LibraryModel.swift#L187-L199)). An A4 preview is 540 × 764 × 4 bytes, about 1.65 MB, so the cache can hold about 390 MB before the system's own pressure eviction; P-11 bounds PDF thumbnails to `min(32 MiB, memory/200)`. Introduced in `2e1b6a2`.
- **Why it matters:** browsing PDF folders while recording a lecture leans on the system's last-moment eviction instead of a budget the app keeps.
- **Fix direction:** a byte budget (`totalCostLimit` with a cost per entry), emptied on a vault switch through the memory-release duty; record it as a P invariant with a test.

#### SRP-SHELL-07 The library adds five `WorkspaceModel` extensions, two feature-named calls in move and delete, and widens two private members
- **Severity:** Medium
- **Rule:** `FR-03`, `FR-04`
- **Evidence:** feature-named calls in the move and delete paths ([WorkspaceModel.swift:1247](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1247), [:1261](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1261)); extension blocks go from 25 to 30 (`WorkspaceLibrary.swift`, `WorkspaceFolderStyles.swift`, `WorkspaceNotebookInsertion.swift`, `LibraryHome.swift`, `WorkspaceFileManagement.swift:384`); `insertEmbed` and `embed(for:in:settings:)` go from private to internal ([WorkspaceModel.swift:913](../../../Sources/GraphiteUI/WorkspaceModel.swift#L913), [:1018](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1018)). No stored property was added. Introduced in `2e1b6a2`.
- **Why it matters:** the next feature that follows paths edits move and remove again.
- **Fix direction:** folder styles become a registered `VaultPathMoveObserver`; the library's wiring moves into a factory the library owns, with narrow capabilities.

#### CC-SHELL-12 Library and New-menu actions start unowned tasks, and a batch of moves continues into the next vault
- **Severity:** Medium
- **Rule:** `FR-66`
- **Evidence:** 13 unowned `Task {}` calls, among them [WorkspaceLibrary.swift:28-31](../../../Sources/GraphiteUI/WorkspaceLibrary.swift#L28-L31), [:48](../../../Sources/GraphiteUI/WorkspaceLibrary.swift#L48), [WorkspaceFolderStyles.swift:17](../../../Sources/GraphiteUI/WorkspaceFolderStyles.swift#L17), [LibraryView.swift:79](../../../Sources/GraphiteUI/LibraryView.swift#L79), [:179](../../../Sources/GraphiteUI/LibraryView.swift#L179), [:282](../../../Sources/GraphiteUI/LibraryView.swift#L282), [GraphiteRootView.swift:485-510](../../../Sources/GraphiteUI/GraphiteRootView.swift#L485-L510); `moveItems` loops over `await self?.move(path, into: folder)` ([WorkspaceLibrary.swift:31](../../../Sources/GraphiteUI/WorkspaceLibrary.swift#L31)) and `move` uses whichever store is current ([WorkspaceFileManagement.swift:111-115](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L111-L115)). Introduced in `2e1b6a2`.
- **Why it matters:** switching vault while moves run applies the remaining old-vault paths to the new vault.
- **Fix direction:** the library model owns a per-vault queue cancelled on a vault switch; views call synchronous intents.

#### OCP-SHELL-08 "New notebook in a note" is declared in three places with three titles, and not in the menu bar
- **Severity:** Medium
- **Rule:** `FR-23`, `FR-33`
- **Evidence:** keyboard toolbar "New Notebook" ([EditorKeyboardToolbar.swift:264-266](../../../Sources/GraphiteUI/EditorKeyboardToolbar.swift#L264-L266), filled at [MarkdownPane.swift:256](../../../Sources/GraphiteUI/MarkdownPane.swift#L256)); More menu "New Notebook…" ([MarkdownPane.swift:475](../../../Sources/GraphiteUI/MarkdownPane.swift#L475)); palette "Notebooks: Insert new notebook" ([WorkspaceCommands.swift:246-251](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L246-L251)). The request is typed out three times, has no plugin gate (the drawing command beside it has one) and is not in `GraphiteCommands`. Introduced in `2e1b6a2`.
- **Fix direction:** declare it once in the editor command table as one `TabDocument` intent.

#### CC-SHELL-13 Notebook creation and file import are each implemented twice in the workspace
- **Severity:** Medium
- **Rule:** `FR-10`
- **Evidence:** [WorkspaceNotebookInsertion.swift:21-45](../../../Sources/GraphiteUI/WorkspaceNotebookInsertion.swift#L21-L45) repeats [WorkspaceModel.swift:860-871](../../../Sources/GraphiteUI/WorkspaceModel.swift#L860-L871); `importFiles` ([WorkspaceFileManagement.swift:388-414](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L388-L414)) repeats `importAttachment` ([WorkspaceModel.swift:874-890](../../../Sources/GraphiteUI/WorkspaceModel.swift#L874-L890)); the new copies drop the error without logging it. Introduced in `2e1b6a2`.
- **Fix direction:** one `NotebookCreator` and one `FileImporter`, each returning a typed outcome.

#### DIP-SHELL-06 Five new persisted keys are private string literals in two types, with no registry and no test of their names
- **Severity:** Medium
- **Rule:** `FR-73`, `FR-95`, `FR-40`
- **Evidence:** keys at `NotebookLibraryPreferences.swift:75-78` at `9040705` (at `5aae924`, after `GraphiteNoteTakingStyle` was removed in `f57a411`, the remaining key is at [NotebookLibraryPreferences.swift:29](../../../Sources/GraphiteUI/NotebookLibraryPreferences.swift#L29)) and [NotebookCreationDefaults.swift:8-12](../../../Sources/GraphiteUI/NotebookCreationDefaults.swift#L8-L12); the tests round-trip values but pin no key name; `NotebookCreationDefaults` has no test; `presentation` is a settable `var` that persists in `didSet` and is assigned from two views ([VaultSidebar.swift:262](../../../Sources/GraphiteUI/VaultSidebar.swift#L262), `NoteTakingStyleViews.swift:66` (deleted in `f57a411`)). Introduced in `2e1b6a2`.
- **Why it matters:** renaming a key silently resets people's choices, and no test notices.
- **Fix direction:** declare the keys in the typed registry with name-pinning tests; `presentation` becomes `private(set)` behind an intent.

#### ISP-SHELL-05 The library's item menu hands the whole `WorkspaceModel` to `VaultEntryMenu`, captured `unowned`
- **Severity:** Low
- **Rule:** `FR-02`
- **Evidence:** [WorkspaceLibrary.swift:41](../../../Sources/GraphiteUI/WorkspaceLibrary.swift#L41) builds `VaultEntryMenu(entry:workspace: self, …)` in a closure captured `[unowned self]`, stored by the view ([LibraryView.swift:36-40](../../../Sources/GraphiteUI/LibraryView.swift#L36-L40)). Introduced in `2e1b6a2`.
- **Why it matters:** the library's only dependency on the whole workspace; `unowned` traps if a menu outlives the workspace during scene teardown.
- **Fix direction:** an item-actions value; capture `weak`.

#### CC-SHELL-14 A production view modifier carries a flag that exists for tests, and reads `UIDevice.current`
- **Severity:** Low
- **Rule:** `FR-32`, `FR-56`, `FR-52`
- **Evidence:** `isAsking` is documented "False for root views made in tests" (`NoteTakingStyleViews.swift:82-83` at `9040705`; the file was deleted in `f57a411`, see the state changes below); the modifier reads `UIDevice.current` (`NoteTakingStyleViews.swift:91` (deleted in `f57a411`)). Introduced in `2e1b6a2`.
- **Fix direction:** the composition root passes one value saying whether to ask (the `LaunchMode` already exists).

#### OCP-SHELL-09 The library filter decides by equality tests on `DocumentKind`
- **Severity:** Low
- **Rule:** `FR-19`
- **Evidence:** `kind == .pdf` and similar tests ([LibraryListing.swift:9-16](../../../Sources/GraphiteCore/LibraryListing.swift#L9-L16)); `.media` matches no filter but "All". Introduced in `7f56e00`.
- **Fix direction:** a `libraryGroup` on `DocumentKind` from one exhaustive switch.

#### CC-SHELL-15 New views add literal sizes, fixed-point fonts and a repeated aspect ratio
- **Severity:** Low
- **Rule:** `FR-78`, `FR-24`
- **Evidence:** grid literals ([LibraryView.swift:52](../../../Sources/GraphiteUI/LibraryView.swift#L52), [:83](../../../Sources/GraphiteUI/LibraryView.swift#L83), [:155](../../../Sources/GraphiteUI/LibraryView.swift#L155)); the page ratio `0.77` three times ([LibraryTiles.swift:54](../../../Sources/GraphiteUI/LibraryTiles.swift#L54), [:69](../../../Sources/GraphiteUI/LibraryTiles.swift#L69), [:84](../../../Sources/GraphiteUI/LibraryTiles.swift#L84)); fixed 7, 8.5 and 10 pt fonts ([LibraryTiles.swift:106-112](../../../Sources/GraphiteUI/LibraryTiles.swift#L106-L112)); corner radius 14 in four places. Introduced in `2e1b6a2`.
- **Fix direction:** `LibraryLayout` constants with units now; design tokens in Phase 13.

#### LSP-SHELL-05 A note whose read fails shows as a blank page, and a failed cloud check reads the file
- **Severity:** Low
- **Rule:** `FR-59`, `FR-80`
- **Evidence:** a failed read returns `(Data(), true)` ([LibraryPreviewLoader.swift:101](../../../Sources/GraphiteApple/LibraryPreviewLoader.swift#L101)), drawn as an empty page ([LibraryTiles.swift:46-47](../../../Sources/GraphiteUI/LibraryTiles.swift#L46-L47)), against the comment two lines above; a failed resource-value check counts the file as downloaded, so the coordinated read can fetch a placeholder ([LibraryPreviewLoader.swift:64-66](../../../Sources/GraphiteApple/LibraryPreviewLoader.swift#L64-L66)). Introduced in `7f56e00`.
- **Fix direction:** return nil (the kind icon); treat an unknown cloud state as not downloaded.

#### CC-SHELL-16 A file created from the library opens its tab before the file exists, and a failure leaves an empty tab
- **Severity:** Low
- **Rule:** `FR-12`
- **Evidence:** the tab opens and the library leaves home before the create task runs ([GraphiteRootView.swift:491-515](../../../Sources/GraphiteUI/GraphiteRootView.swift#L491-L515)); a failed create only sets `errorMessage` ([WorkspaceModel.swift:870](../../../Sources/GraphiteUI/WorkspaceModel.swift#L870)); `case .notebook: break` is dead ([GraphiteRootView.swift:503](../../../Sources/GraphiteUI/GraphiteRootView.swift#L503)). Introduced in `2e1b6a2`.
- **Fix direction:** open the tab only after the create returns the new path.

#### State changes of earlier findings (library)
All worse, none fixed:
- `SRP-SHELL-01`: five more extension blocks (25 → 30), two feature-named calls, two members widened (`SRP-SHELL-07`).
- `SRP-SHELL-03`, `CC-SHELL-06`: `errorMessage` writers go from 86 to 90, none logging the error; about 60 new literal user strings; `FolderColor.title` builds words from a persisted raw value ([LibraryTiles.swift:146](../../../Sources/GraphiteUI/LibraryTiles.swift#L146), `FR-28`).
- `SRP-SHELL-04`: the root view gains one `@State`, one flag, the question and creation sheets and a sidebar-visibility rule (shorter overall only because the notebook form moved out).
- `SRP-SHELL-06`: two more stored properties on `GraphitePreferences` ([GraphitePreferences.swift:209-211](../../../Sources/GraphiteUI/GraphitePreferences.swift#L209-L211)); one-area types, which is the right shape.
- `OCP-SHELL-05`: `CreatableItem` is an eighth list of creatable kinds ([NewItemPicker.swift:5-66](../../../Sources/GraphiteUI/NewItemPicker.swift#L5-L66)); its `requiredPlugin` field is the right shape.
- `OCP-SHELL-01`: three more per-kind tables plus `LibraryFilter`, each an exhaustive switch.
- `ISP-SHELL-03`: views assign `workspace.fileSheet` and `preferences.library.presentation`.
- `CC-SHELL-05`: two more duplicated pieces (`CC-SHELL-13`).
- `ISP-EDITOR-02`: `EditorActions` gains a fifteenth optional closure, `newNotebook`.
- `ISP-SHELL-01`: unchanged (72 stored `WorkspaceModel` declarations by its own count).

#### Patterns to keep (library)
- `FolderStyleList` keeps what it does not understand (unknown colours, keys and entries), refuses a wrongly shaped file instead of overwriting it, writes with a revision check and creates the file only once a style exists ([FolderStyleList.swift:17-127](../../../Sources/GraphiteCore/FolderStyleList.swift#L17-L127)).
- `LibraryView` receives `LibraryVault`, `LibraryActions` and `LibraryEntryPresentation` values, and `LibraryModel` is tested without a workspace.
- `LibraryListing.items`, `NotebookPlacement.insertedText`, `NotebookPageSize` and `NotePreviewSummary` (which reads at most 4 KB) are pure Core functions tested with values.
- `PaperPreviewRenderer` draws the generator's own PDF, so a paper picture cannot differ from the notebook it makes.

### Other shell changes (fff794b)

Phase 0 and Phase 1 commits changed the workspace, the root view, the Mac scenes and the vault store; new files are `WorkspaceDeviceServices.swift`, `WorkspaceScenePhase.swift`, `QuitSaveDecision.swift`, `ExclusiveOperationRunner.swift`, `LaunchMode.swift`, `ApplicationClock.swift` and `ApplicationFolders.swift`. The polled rename-outcome dictionary is recorded once, as `CC-PLUGIN-15` in [plugin.md](plugin.md) section 9 (alias of this audit's draft `SRP-SHELL-51`).

#### BUG-SHELL-10 When a vault's Templates or Daily notes settings cannot be read, the previous vault's settings stay in force and can create a daily note in the new vault
- **Severity:** Medium (verdict: Confirmed, traced by the lead)
- **Rule:** `FR-59`, `FR-12`
- **Evidence:** traced path, introduced in `877045a`:
  1. `templateSettings` and `dailyNoteSettings` are workspace fields ([WorkspaceModel.swift:150-151](../../../Sources/GraphiteUI/WorkspaceModel.swift#L150-L151)) that only `reloadVaultSettings` and the two setters assign; `openVault` does not reset them.
  2. `openVault` calls `reloadVaultSettings()` ([WorkspaceModel.swift:381](../../../Sources/GraphiteUI/WorkspaceModel.swift#L381)).
  3. In the new vault, `templates.json` or `daily-notes.json` exists but cannot be read (for example over 1 MiB, [VaultStore.swift:70](../../../Sources/GraphiteCore/VaultStore.swift#L70)), so `configurationData` and the settings getter throw ([VaultStore.swift:259-263](../../../Sources/GraphiteCore/VaultStore.swift#L259-L263)).
  4. The `catch` only sets `errorMessage` ([WorkspaceModel.swift:423-426](../../../Sources/GraphiteUI/WorkspaceModel.swift#L423-L426)); both fields keep the old vault's values, and a failure on the first line skips `daily-notes.json` too.
  5. `dailyNoteSettings.opensOnStartup` still holds the old vault's value ([WorkspaceModel.swift:387](../../../Sources/GraphiteUI/WorkspaceModel.swift#L387)), so `openDailyNote` creates a note in the new vault, in the old vault's folder with its date format and template.
- **Why it matters:** a file is written into a vault from another vault's settings, and the settings screens show the other vault's values. Before `877045a` a failed read gave defaults instead.
- **Fix direction:** one per-vault settings value that `openVault` replaces, with an `unreadable` case per file; startup actions and settings screens act only on read or missing settings. Regression test with two vaults, one with an oversized `daily-notes.json`.

#### BUG-SHELL-11 A plugin's rename is answered "not renamed" when the move takes longer than 10 s after the person answers, although the file moved
- **Severity:** Low (verdict: Confirmed by the auditor's trace)
- **Rule:** `FR-29`, `FR-12`, `FR-65`
- **Evidence:** after "Update Links", a 10 s deadline starts ([CommunityPluginHost.swift:998-1001](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L998-L1001)); `completeMove` saves every document, moves, rewrites links and refreshes before it stores the outcome ([WorkspaceFileManagement.swift:185-214](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L185-L214), [:176](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L176)); past the deadline the host returns `.refused(.cancelled)` ([CommunityPluginHost.swift:1005](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1005)), and a dismissal always holds the plugin the full 10 s. Introduced in `4489db2`.
- **Why it matters:** the plugin acts on a failure that did not happen.
- **Fix direction:** `move` awaits its final outcome through a continuation that `resolve` and the dismissal complete (the fix of `CC-PLUGIN-15`).

#### BUG-SHELL-12 `graphite://read?file=X` opens the note but reads nothing when X is already open on the other side of the split
- **Severity:** Low (verdict: Confirmed by the auditor's trace)
- **Rule:** `FR-12`, `FR-13`
- **Evidence:** `.read` reads only the path `openLinkedFile` returns ([WorkspaceDeepLinks.swift:39-47](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L39-L47)), which it returns only when `selection == linkedPath` after `follow` ([:93-95](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L93-L95)); `follow` opens with `takesFocus: false` ([WorkspaceModel.swift:714-717](../../../Sources/GraphiteUI/WorkspaceModel.swift#L714-L717)), and an already open file is revealed without moving focus ([:490-491](../../../Sources/GraphiteUI/WorkspaceModel.swift#L490-L491)). Introduced in `d75f41c`.
- **Why it matters:** a Shortcut that asks Graphite to read a note silently does nothing in a common split layout.
- **Fix direction:** return the tab and path that `open` reported, or open with `takesFocus: true` for this link.

#### LSP-SHELL-06 `completeMove` reports `.moved` when some linking notes were not updated
- **Severity:** Low
- **Rule:** `FR-29`, `FR-12`
- **Evidence:** link-update failures and edits kept as copies go only to `errorMessage`, and the function returns `.moved` ([WorkspaceFileManagement.swift:207-214](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L207-L214)); the plugin is answered success ([CommunityPluginHost.swift:986-987](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L986-L987)). Introduced in `4489db2`.
- **Fix direction:** `.moved(FileMoveReport)` with the failed notes and kept copies.

#### DIP-SHELL-07 The launch mode is read as a flag inside the root view, and a test-only scene initializer picks `.normal`
- **Severity:** Low
- **Rule:** `FR-56`, `FR-32`
- **Evidence:** `GraphiteRootView` stores `restoresLastVault`, set in three initializers and branched on in `.task` ([GraphiteRootView.swift:10](../../../Sources/GraphiteUI/GraphiteRootView.swift#L10), [:50-70](../../../Sources/GraphiteUI/GraphiteRootView.swift#L50-L70), [:217](../../../Sources/GraphiteUI/GraphiteRootView.swift#L217)); `GraphiteMacScenes.init(workspace:)` sets `.normal` for tests ([GraphiteMacScenes.swift:21-23](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L21-L23)). Introduced in `0c074d9`.
- **Fix direction:** the workspace carries a restore policy and the view calls one launch intent; the test initializer moves to test support.

#### CC-SHELL-17 The new outcome types carry prose and `localizedDescription` instead of facts
- **Severity:** Medium
- **Rule:** `FR-55`, `FR-63`, `FR-64`, `FR-13`
- **Evidence:** `FileMoveRefusal.failed(message: String)` holds `localizedDescription` and the enum writes its own sentences ([WorkspaceFileManagement.swift:35-46](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L35-L46), `4489db2`); `QuitBlockingReason.saveFailed(errorDescription:)` stores `localizedDescription`, always says "Resolve the conflict" ([QuitSaveDecision.swift:21](../../../Sources/GraphiteUI/QuitSaveDecision.swift#L21), [:42](../../../Sources/GraphiteUI/QuitSaveDecision.swift#L42), `e4feaa1`), and `allowsTermination` is stored though it derives from `blockingReason == nil`; the settings read error builds a sentence ([WorkspaceModel.swift:426](../../../Sources/GraphiteUI/WorkspaceModel.swift#L426), `877045a`).
- **Why it matters:** the typed error is lost at the first hop, a disk-full error at quit is called a conflict, and each message overwrites the shared `errorMessage`.
- **Fix direction:** carry the typed error; derive `allowsTermination`; one presenter words every case.

#### CC-SHELL-18 The Mac quit deadline is a hand-written timeout race on the system clock
- **Severity:** Low
- **Rule:** `FR-67`, `FR-50`, `FR-40`, `FR-43`
- **Evidence:** two unowned tasks race, the deadline uses `Task.sleep` on the system clock ([GraphiteMacScenes.swift:59-68](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L59-L68)) though the workspace has `clock`; a settable `var deadline` and a `hasReplied` flag let the first outcome win ([:79](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L79)); the delegate assigns `workspace.errorMessage` ([:92](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L92)). Introduced in `e4feaa1`.
- **Why it matters:** the 5 s rule cannot be tested without waiting 5 s, and it is another hand-written "first outcome wins" (`CC-ARCH-04`).
- **Fix direction:** a workspace intent `saveForQuit(deadline:) async -> QuitSaveDecision` racing on `clock` through one `withTimeout` primitive.

#### CC-SHELL-19 Moving a folder commits a canvas's text edit from inside a query, and the new canvas lines repeat untyped decisions
- **Severity:** Low
- **Rule:** `FR-08`, `FR-05`, `FR-58`, `FR-24`
- **Evidence:** `unsavedEdits(...)` calls `session.commitTextEdit()` inside a `compactMap` ([WorkspaceFileManagement.swift:250-262](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L250-L262)); the extensions `"md"` and `"canvas"` are literals; the revision loop is duplicated per document kind ([:239-247](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L239-L247)). Introduced in `4660830`.
- **Fix direction:** commit pending edits as a named step first; each session reports its pending data and kind, the extension from the kind's descriptor.

#### CC-SHELL-20 `scenePhaseDidChange` starts an unowned task, and the background save stays owned by the view
- **Severity:** Low
- **Rule:** `FR-66`, `FR-09`
- **Evidence:** the activation `Task {…}` is never stored or cancelled ([WorkspaceScenePhase.swift:15](../../../Sources/GraphiteUI/WorkspaceScenePhase.swift#L15)); the save is a closure from the view ([:9](../../../Sources/GraphiteUI/WorkspaceScenePhase.swift#L9), [:18](../../../Sources/GraphiteUI/WorkspaceScenePhase.swift#L18)). Moved unchanged from the root view in `0c074d9` (`CC-ARCH-05` carried into a new file).
- **Fix direction:** store the task and cancel it on the next phase change; the workspace owns the save with a background-task capability.

#### CC-SHELL-21 Five new or changed lines exceed 160 characters
- **Severity:** Low
- **Rule:** `FR-76`
- **Evidence:** QuitSaveDecision.swift:21 (203) and :23 (176); WorkspaceFileManagement.swift:42 (179) and :176 (166); WorkspaceModel.swift:698 (161). The `lines-over-160-characters` gate counts them in its baseline.
- **Fix direction:** wrap them; the gate's baseline goes down with each.

#### State changes of earlier findings (fff794b)
- `SRP-SHELL-01`: **Worse**: four more stored properties (`deviceDefaults`, `applicationFolders`, `clock`: planned injection; `answeredMoveOutcomes`: feature state).
- `SRP-SHELL-02`: **Worse**: a new reset line in the vault switch (`answeredMoveOutcomes = [:]`, [WorkspaceModel.swift:358](../../../Sources/GraphiteUI/WorkspaceModel.swift#L358)).
- `CC-SHELL-06`: **Worse**: three more model-side sentence builders (`CC-SHELL-17`).
- `BUG-SHELL-02`, `OCP-SHELL-06`, `LSP-SHELL-02`, `DIP-SHELL-03`, `DIP-SHELL-04`, `CC-SHELL-02`: unchanged.

#### Patterns to keep (fff794b)
- `QuitSaveDecision` is a pure, tested decider: quitting waits for the save and refuses on failure (`FR-05`, `FR-60`).
- `configurationData` keeps "missing" apart from "unreadable" and has tests ([VaultStore.swift:256-263](../../../Sources/GraphiteCore/VaultStore.swift#L256-L263), `FR-59`).
- A canvas's edits during a move are saved against the pre-move revision or kept as a copy, never overwritten ([WorkspaceFileManagement.swift:270-292](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L270-L292)).

### Changes merged after 9040705 (5aae924)

Delta audit of 2026-10-20 at `5aae924` (main): the library's fixes (`bf86b5d`, `6a6dae3`, `21e33ad`, `f57a411`), Read Aloud as a switchable core plugin (`38581b0`), the test-silence seam (`32787b2`, `96cfabb`) and the race fixes (`a724bd5`, `cd80070`). The Goodnotes and Notability readers of the same range are in [import.md](import.md).

#### DIP-SHELL-08 Test silence is decided by checking the process from inside production types, not by the composition root
- **Severity:** Medium
- **Rule:** `FR-56`, `FR-32`, `FR-47`, `FR-54` ("fakes, not flags")
- **Evidence:** `AudioOutputRoute.thisProcess` parses `LaunchMode` again from `ProcessInfo` and checks `NSClassFromString("XCTestCase")` inside GraphiteCore ([LaunchMode.swift:50-56](../../../Sources/GraphiteCore/LaunchMode.swift#L50-L56)), although the app parses the launch mode once ([GraphiteApp.swift:17](../../../App/GraphiteApp.swift#L17)); `AppleReadAloudSpeech`, `NeuralReadAloudSpeech` and `RenderedPassagePlayer` default their `output:` to it ([ReadAloudSpeech.swift:184](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L184), which also defaults `clock = LiveApplicationClock()`; [NeuralReadAloudSpeech.swift:38](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L38); [RenderedPassagePlayer.swift:28](../../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L28)); embedded media reads the static directly ([MarkdownPreview.swift:2742](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2742)); the composition seam exists (`makeReadAloudController`), but the live and hosted-tests branches pass the same factory ([WorkspaceDeviceServices.swift:45](../../../Sources/GraphiteUI/WorkspaceDeviceServices.swift#L45), [:64](../../../Sources/GraphiteUI/WorkspaceDeviceServices.swift#L64)). Introduced in `32787b2`, extended in `96cfabb`.
- **Why it matters:** the owner's rule that tests never play sound holds today, but through four production types in three modules asking "am I under test"; a new audio type or caller gets the check only if it remembers the default. It is the general form of the `CC-SHELL-14` break that was just removed.
- **Fix direction:** `WorkspaceDeviceServices` maps `LaunchMode` to a route once (`AudioOutputRoute(launchMode:)` exists) and passes it to the speech factory and, through an environment value, to embedded media; package tests pass `.silent` explicitly; delete `thisProcess` and the `= .thisProcess` and `= LiveApplicationClock()` defaults. Keep the no-sound guarantee as a test: a hosted launch's composition has no speaker route.

#### LSP-SHELL-07 `checkOpenDocumentsForExternalChanges` gains a parameter that only a test passes
- **Severity:** Medium
- **Rule:** `FR-32`, `FR-47`
- **Evidence:** `openChangedPDF: ((URL, String?) async throws -> PDFSession)? = nil`, replaced inside the callee by `openPDFSession` ([WorkspaceModel.swift:1430-1444](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1430-L1444)); no production caller passes it, only `UiWorkspaceModelFixTests.swift:275`. Introduced in `cd80070`.
- **Why it matters:** the application aggregate's API grows for one test, and the test exercises a path production never takes.
- **Fix direction:** the workspace receives its PDF-opening capability at construction; the test gates that capability.

#### SRP-SHELL-08 `WorkspaceModel` takes on Read Aloud's lifecycle through an equality test on the plugin, and "Read Aloud is on" has two sources
- **Severity:** Medium
- **Rule:** `FR-03`, `FR-19`, `FR-17`, `FR-13`, `FR-40`
- **Evidence:** a new stored `makeReadAloudController`, with `readAloud` and `readAloudNavigator` now mutable ([WorkspaceModel.swift:191-198](../../../Sources/GraphiteUI/WorkspaceModel.swift#L191-L198)); `setCorePluginEnabled` branches on `guard plugin == .readAloud` ([:241-244](../../../Sources/GraphiteUI/WorkspaceModel.swift#L241-L244)); `startReadAloud`/`endReadAloud` wire the navigator's closures inside the aggregate ([:247-268](../../../Sources/GraphiteUI/WorkspaceModel.swift#L247-L268)); "on" is read both as `preferences.isEnabled(.readAloud)` ([WorkspaceDeepLinks.swift:41](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L41), [SettingsView.swift:168](../../../Sources/GraphiteUI/SettingsView.swift#L168)) and as `readAloud != nil` ([MarkdownPane.swift:540](../../../Sources/GraphiteUI/MarkdownPane.swift#L540), [WorkspacePanes.swift:255](../../../Sources/GraphiteUI/WorkspacePanes.swift#L255)), which agree only while every change goes through `setCorePluginEnabled`; `GraphitePreferences.setEnabled` stays callable ([GraphitePreferences.swift:427](../../../Sources/GraphiteUI/GraphitePreferences.swift#L427)). Introduced in `38581b0`.
- **Why it matters:** the next plugin that runs something adds another `== .x` branch and start/end pair to the aggregate; a direct `setEnabled(.readAloud, …)` leaves switch and controller disagreeing.
- **Fix direction:** `CorePlugin`'s descriptor carries an optional activation the Read Aloud module registers; a Read Aloud feature owner holds controller and navigator; `setEnabled` reachable only through that intent.

#### SRP-SHELL-09 `LibraryModel` adds a render scheduler and a file-repair policy and reaches 15 stored properties
- **Severity:** Low
- **Rule:** `FR-01`, `FR-96`
- **Evidence:** `waitingPreviews` and `requestedPreviewKeys` take the class to 15 stored properties ([LibraryModel.swift:44-54](../../../Sources/GraphiteUI/LibraryModel.swift#L44-L54)); it holds listing, style repair and a preview scheduler of 5 fields and 9 functions ([:85-242](../../../Sources/GraphiteUI/LibraryModel.swift#L85-L242)). Introduced in `bf86b5d`.
- **Fix direction:** extract `LibraryPreviewScheduler` and test it without the model.

#### CC-SHELL-22 The damaged-style-file repair is decided in the UI model, with no vault check, under an unversioned name
- **Severity:** Medium
- **Rule:** `FR-05`, `FR-61`, `FR-12`
- **Evidence:** `LibraryModel.loadFolderStyles` decides "not Graphite's format, move aside" and runs the move ([LibraryModel.swift:116-131](../../../Sources/GraphiteUI/LibraryModel.swift#L116-L131)), applying results after its awaits with no check of the vault ([:110](../../../Sources/GraphiteUI/LibraryModel.swift#L110), [:119](../../../Sources/GraphiteUI/LibraryModel.swift#L119)); overlapping listings (`show` from unowned tasks, [LibraryView.swift:100](../../../Sources/GraphiteUI/LibraryView.swift#L100), [:223](../../../Sources/GraphiteUI/LibraryView.swift#L223)) can both read the bad file, the second move throws, and the notice says the file "is left as it is" although it was moved ([LibraryView.swift:85-86](../../../Sources/GraphiteUI/LibraryView.swift#L85-L86)); a listing in flight across a vault switch can apply the old vault's colours or alert; the kept name `graphite-folder-styles.unreadable.json` has no version. Introduced in `bf86b5d`.
- **Why it matters:** a destructive file decision lives in a view model where overlapping calls race, and the person can be told the wrong thing about their file.
- **Fix direction:** one store call (`readOrSetAsideFolderStyles()`) returning `contents`, `missing` or `setAside(VaultPath)`, deciding and moving inside the store actor under a versioned name; the model applies it only for the same vault.

#### CC-SHELL-23 The render limit counts tasks, not renders, and renders now run at user-initiated priority
- **Severity:** Medium
- **Rule:** `FR-72`, `FR-105`, `FR-69`
- **Evidence:** `previewTasks` is documented "never more than `maximumConcurrentRenders`" ([LibraryModel.swift:44](../../../Sources/GraphiteUI/LibraryModel.swift#L44)), but `cancelPreview` frees the slot at once ([:226-229](../../../Sources/GraphiteUI/LibraryModel.swift#L226-L229)) while the loader checks cancellation only before its synchronous `firstPage` and `picture` calls ([LibraryPreviewLoader.swift:43-47](../../../Sources/GraphiteApple/LibraryPreviewLoader.swift#L43-L47)), so every started decode runs to completion beside four new ones; renders run at the main-actor task's priority ([LibraryModel.swift:205](../../../Sources/GraphiteUI/LibraryModel.swift#L205)) where they ran at `.utility` before. Introduced in `bf86b5d`.
- **Why it matters:** a fling over PDFs runs many concurrent decodes at UI priority, against Pencil and typing; the stated bound is not the real one.
- **Fix direction:** count a cancelled render against the limit until its task returns; start render tasks at `.utility`.

#### CC-SHELL-24 The library's note page restates reading view's callout table, and the two disagree
- **Severity:** Medium
- **Rule:** `FR-10`, `FR-21`, `FR-24`
- **Evidence:** `calloutSymbol` and `calloutColor` ([LibraryNotePage.swift:126-149](../../../Sources/GraphiteUI/LibraryNotePage.swift#L126-L149)) restate reading view's table ([MarkdownPreview.swift:2554-2570](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2554-L2570)), which also resolves aliases through `ObsidianCalloutTypes.canonicalType`; they disagree for `bug`, `danger`/`error`, `success`, unknown types and the `abstract` family, and the tile ignores the vault theme's callout colours. Introduced in `6a6dae3`.
- **Fix direction:** one callout style descriptor keyed by `ObsidianCalloutTypes`, used by both.

#### CC-SHELL-25 The Library/List switch is declared twice, and the presentation gains a third writer
- **Severity:** Low
- **Rule:** `FR-24`, `FR-40`
- **Evidence:** the same "Show Files As" picker at [LibraryView.swift:414-418](../../../Sources/GraphiteUI/LibraryView.swift#L414-L418) and [LibrarySettingsSection.swift:11-13](../../../Sources/GraphiteUI/LibrarySettingsSection.swift#L11-L13); `presentation` ([NotebookLibraryPreferences.swift:34](../../../Sources/GraphiteUI/NotebookLibraryPreferences.swift#L34)) is assigned in three places. Introduced in `21e33ad` and `f57a411`.
- **Fix direction:** reuse `LibraryPresentationSwitch`; `presentation` becomes `private(set)` behind an intent.

#### CC-SHELL-26 The library notice title is an `if`/`else` over `LibraryFailure` that ends in a fallback
- **Severity:** Low
- **Rule:** `FR-18`
- **Evidence:** `library.failure == .styleNotSaved ? "Folder Look Not Saved" : "Folder Colors Reset"` ([LibraryView.swift:74-76](../../../Sources/GraphiteUI/LibraryView.swift#L74-L76)) beside an exhaustive switch for the message. Introduced in `bf86b5d`.
- **Fix direction:** one notice value (title and message) from one exhaustive switch.

#### CC-SHELL-27 The Read Aloud migration restates the voices folder and the Read Aloud key family, and treats an unlistable folder as "no voice"
- **Severity:** Low
- **Rule:** `FR-10`, `FR-24`, `FR-51`, `FR-59`
- **Evidence:** `voicesFolder(in:)` ([CorePluginSwitches.swift:104-109](../../../Sources/GraphiteUI/CorePluginSwitches.swift#L104-L109)) restates `NeuralVoiceCatalog.voicesFolder()`; `readAloudPreferencePrefixes` ([:85-91](../../../Sources/GraphiteUI/CorePluginSwitches.swift#L85-L91)) is a third spelling of keys declared privately elsewhere; `folderHoldsVoice` calls `FileManager` from the UI module and its `try?` makes an unlistable folder mean "no voice" ([:96-100](../../../Sources/GraphiteUI/CorePluginSwitches.swift#L96-L100)). Introduced in `38581b0`.
- **Why it matters:** a moved voices folder, a renamed key or a listing failure turns Read Aloud off, once and for good, for someone who used it.
- **Fix direction:** take the folder from `NeuralVoiceCatalog`, the key list from one registry, and report `unreadable` as its own evidence case.

#### State changes of earlier findings (5aae924)
- `CC-SHELL-14`: Open → **Fixed**. `NoteTakingStyleViews.swift` was deleted in `f57a411` and the root view no longer carries the flag; the rule break moved and grew (`DIP-SHELL-08`).
- `DIP-SHELL-06`: unchanged, mixed: one key fewer (`GraphiteNoteTakingStyle` removed), four private literals remain, and `presentation` has three writers (`CC-SHELL-25`).
- `SRP-SHELL-01`: **Worse by one** stored property (`makeReadAloudController`, `SRP-SHELL-08`).
- `SRP-SHELL-07`, `CC-SHELL-12`, `CC-SHELL-13`, `ISP-SHELL-05`, `CC-SHELL-16`, `BUG-SHELL-10`: unchanged at `5aae924`.

#### Patterns to keep (5aae924)
- Availability is data: while Read Aloud is off no speech engine exists, and views get `ReadAloudController?` and `offersReadAloudPen` instead of re-checking a preference ([MarkdownPane.swift:590-592](../../../Sources/GraphiteUI/MarkdownPane.swift#L590-L592)).
- `CorePluginSwitches` is a pure value with pinned keys, and the migration splits a pure decision with an evidence value from the step that writes it ([CorePluginSwitches.swift:69-82](../../../Sources/GraphiteUI/CorePluginSwitches.swift#L69-L82)).
- The preview cache enforces a named byte budget, each entry costing its decoded pixels ([LibraryModel.swift:22-27](../../../Sources/GraphiteUI/LibraryModel.swift#L22-L27)).
