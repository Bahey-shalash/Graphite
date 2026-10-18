# Interface segregation (ISP): synthesis across all areas
Snapshot: b13dec3 (main, 2026-10-18).

Scope: the 40 `ISP-*` findings of the twelve area audits and the architecture audit, as listed in [findings-index.md](../findings-index.md) (3 High, 20 Medium, 17 Low). Each High finding and each systemic pattern below was checked against the snapshot. Source links start with `../../../`. Area links start with `../areas/`.

Throughout, "interface" means whatever a consumer receives: a stored model reference, a protocol, a struct of closures, an environment value, a dictionary payload, or the settable properties of an object. The question is always the same: how much of what a consumer receives does it actually use, and how much can it change that it should not?

## 1. Verdict by area

| Area | Area verdict (I) | High | Medium | Low | Reason, with numbers |
| --- | --- | ---: | ---: | ---: | --- |
| [SHELL](../areas/shell.md) | Weak | 1 | 2 | 1 | 51 view declarations in the area's files take the whole `WorkspaceModel`. `VaultItemDragPreview` uses 1 member and `TabSwitcher` 7. `CommunityPluginHost` reads 23 workspace members through a back-reference. `store`, `index`, `folderAccess` and `layout` can be set from anywhere. |
| [EDITOR](../areas/editor.md) | Mixed | 0 | 2 | 3 | `MarkdownStyledTextView` (5 members) and `RetainableMarkdownEditor` (3) are narrow. `EditorActions` has 13 optional members per platform. `LivePreviewEnvironment` has 25 members. `MarkdownSession` holds `VaultStore` to use 5 operations. The text views expose 12 (iPad) and 14 (Mac) settable closure slots. |
| [READING](../areas/reading.md) | Mixed | 0 | 2 | 1 | `MarkdownPane` uses 38 `WorkspaceModel` members and writes 6 workspace fields. Panes overwrite the window's Read Aloud closure, and the last writer wins. `PropertiesPanel`, `ReadingTaskContext` and `ReadingImageActions` take only closures. |
| [MDCORE](../areas/mdcore.md) | Mostly strong | 0 | 0 | 2 | Almost every entry point is a static function from values to values. The gaps: `LocatedBlock` has 3 fields that each apply to one case, and YAML frontmatter crosses into indexing as `Any`. |
| [VAULT](../areas/vault.md) | Mixed | 0 | 1 | 2 | `VaultStore` has 24 public methods in its main file, plus extensions in 3 files. Sessions use 4 or 5 of them. `ConflictVersionStore` combines 3 discovery and 3 destructive requirements. 12 `[String: Any]` in scope. |
| [BASES](../areas/bases.md) | Mixed | 0 | 2 | 1 | `BaseRecordProvider` has 3 requirements, which is good. Every Bases entry point takes the whole `VaultStore` (uses 4 members) and `VaultIndex` (uses 5). The view writes `actionErrorMessage` and `loadedContentVersion`. `BaseViewActions` has 9 members and goes to every cell. |
| [CANVAS](../areas/canvas.md) | Mixed | 0 | 2 | 2 | `CanvasPane` uses 20 `WorkspaceModel` members. The graph and map panels take a `MarkdownSession` to read `path`. Views write 6 session fields directly. `CanvasSession` uses 4 `VaultStore` members. |
| [INK](../areas/ink.md) | Mixed | 0 | 1 | 1 | `LassoCanvasContent` has 11 requirements (see Corrections). `LassoAreaCapture` uses 2 of them, and one conformer stubs 5. `InfiniteCanvasView` exposes 10 settable callback and configuration fields to its one owner. |
| [LECTURE](../areas/lecture.md) | Mixed | 0 | 1 | 3 | Views set 10 `PDFSession` fields directly. `PDFPaneHealthMonitor` uses 9 members of the whole coordinator. 8 `[String: Any]` diagnostic payloads. Recording views take the workspace to use 5 members. `PDFInkCanvasProvider` (2 requirements) is the good example. |
| [VOICE](../areas/voice.md) | Mixed | 0 | 3 | 0 | `ReadAloudSpeaking` has 16 requirements covering 6 concerns. 67 view lines reach through `reader.session.`. The pronunciation file is read as `[String: Any]` and written as `[String: String]`, which drops `ipa` (BUG-VOICE-10). |
| [PLUGIN](../areas/plugin.md) | Weak | 1 | 2 | 0 | The host reaches 23 workspace members, and about 20 declarations hold the whole host. 21 host properties are writable from outside. 96 lines in scope carry `[String: Any]`, read with silent defaults. |
| [RUNTIME](../areas/runtime.md) | Mixed | 0 | 2 | 0 | Every host message is an inline object literal, and the Swift side parses it field by field. 9 ad hoc fields are written onto leaves, views and the vault from files that do not own them. |
| [ARCH](../cross-cutting/architecture.md) | Weak | 1 | 0 | 1 | The whole `WorkspaceModel` is taken by 70 stored declarations in 23 files (ARCH says 74 in 27; see Corrections). There are 132 `[String: Any]` in production code ([metrics.md](../metrics.md)). |
| **All** | | **3** | **20** | **17** | **40 findings** |

**App-wide verdict: Weak.** Where narrow interfaces exist, they are well cut: the editor's two ports, `BaseRecordProvider`, `PDFInkCanvasProvider`, and the reading view's closure values. But they are the exception. The application root `WorkspaceModel` and the vault actor `VaultStore` are handed whole to almost every feature, and views mutate model state through public setters instead of intents. Messages to the plugin runtime and to diagnostics travel as untyped dictionaries.

## 2. Systemic patterns across the whole app

The patterns are ordered by cost, highest first.

### 2.1 The application root is every consumer's interface

**What it is.** Views, panels, services and the plugin host keep a reference to the whole `WorkspaceModel`, even when they use one to forty of its members. `WorkspaceModel` is the 86-stored-property aggregate described in `SRP-ARCH-01`.

**Where it occurs.** Seven areas: [ISP-ARCH-01](../cross-cutting/architecture.md#isp-arch-01-74-declarations-take-the-whole-workspacemodel-to-use-a-few-members) (ARCH), [ISP-SHELL-01](../areas/shell.md#isp-shell-01-51-view-declarations-in-scope-take-the-whole-workspacemodel-to-use-one-to-seven-members) and [ISP-SHELL-02](../areas/shell.md#isp-shell-02-communitypluginhost-and-workspacemodel-reference-each-other-the-host-reads-about-23-workspace-members) (SHELL), [ISP-PLUGIN-01](../areas/plugin.md#isp-plugin-01-the-host-takes-the-whole-workspace-and-views-take-the-whole-host) (PLUGIN), [ISP-READING-01](../areas/reading.md#isp-reading-01-the-note-pane-and-the-inspector-take-the-whole-workspacemodel) (READING), [ISP-CANVAS-01](../areas/canvas.md#isp-canvas-01-canvaspane-and-canvasfilepicker-take-the-whole-workspacemodel-for-about-20-members) and `ISP-CANVAS-03` (CANVAS), [ISP-LECTURE-01](../areas/lecture.md#isp-lecture-01-recording-views-take-the-whole-workspacemodel-to-use-five-members) (LECTURE), [ISP-EDITOR-03](../areas/editor.md#isp-editor-03-suggestions-take-the-whole-workspace) (EDITOR).

**Evidence.**
- grep `(let|var) workspace: WorkspaceModel` over `Sources/**` finds 70 stored declarations in 23 files. One of them is the owner: `@State private var workspace` at [GraphiteMacScenes.swift:9](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L9). The other 69 are consumers.
- 17 more function parameters of type `WorkspaceModel` sit in 7 files (initializers not counted), for example [WorkspaceCommands.swift:24](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L24) and [EditorCompletion.swift:100](../../../Sources/GraphiteUI/EditorCompletion.swift#L100).
- `VaultItemDragPreview` holds the workspace to call `preferences.displayName(for:)` once ([VaultSidebar.swift:822-828](../../../Sources/GraphiteUI/VaultSidebar.swift#L822-L828)).
- `TabSwitcher` holds it for `layout` and five tab intents ([TabSwitcher.swift:8-11](../../../Sources/GraphiteUI/TabSwitcher.swift#L8-L11)).
- The plugin host keeps a back-reference, `weak var workspace: WorkspaceModel?` ([CommunityPluginHost.swift:258](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L258)). Through it, the host's own files reach 23 members. One of them is `store`, and the host calls `store.delete` on it directly ([CommunityPluginHost.swift:632-635](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L632-L635)).
- Other heavy users: `MarkdownPane` uses 38 members ([MarkdownPane.swift:9](../../../Sources/GraphiteUI/MarkdownPane.swift#L9)) and `CanvasPane` uses 20 ([CanvasPane.swift:11](../../../Sources/GraphiteUI/CanvasPane.swift#L11)).
- The reach also runs the other way: `LivePreviewEnvironment` carries the whole host (`pluginCodeBlocks: CommunityPluginHost?`, [LivePreviewWidgets.swift:77](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L77)).

**Concrete cost.**
- No view in these 23 files can be previewed or unit-tested without a full workspace. A full workspace means real `UserDefaults.standard`, the real recorder and the real plugin host (`DIP-SHELL-01`). This is why every plugin-host test is a hosted app test (`ISP-PLUGIN-01`).
- Any of the 69 consumers can mutate any workspace state. For example, the sidebar writes `searchResults` and the panes write `layout.splitFraction` (`ISP-SHELL-01`).
- Observation dependencies are invisible. The redraw-avoidance work in SHELL section 6 exists because of this.
- The aggregate cannot be split (the SHELL blueprint) without touching all 86 consumer sites.

**Shared fix direction.**
- Each consumer receives one of three things: the narrow model it shows (`TabWorkspace`, `VaultSearch`, `GraphitePreferences`), a value plus intent closures, or a capability value of at most 7 members.
- The plugin host is the one consumer that gets a protocol, `PluginWorkspaceAccess`, because its tests need a fake (SHELL blueprint row; `ISP-PLUGIN-01` lists `EditorSessionAccess`, `WorkspaceNavigation` and `AppearanceSettings`).
- Start with the leaf views named in SHELL blueprint step 11: `TabSwitcher`, `SearchResultRow`, `VaultItemDragPreview`, `ConflictVersionsBanner` and the settings pages.

### 2.2 The whole vault actor where a session needs four file operations

**What it is.** Document sessions and feature models store `VaultStore` and `VaultIndex` themselves, although they use a handful of read and revision-checked save operations. With them, they receive `move`, `delete`, `saveSettings` and index rebuilds.

**Where it occurs.** Five areas: [ISP-VAULT-01](../areas/vault.md#isp-vault-01-consumers-that-need-four-or-five-file-operations-receive-all-32-vaultstore-methods) (VAULT), [ISP-EDITOR-01](../areas/editor.md#isp-editor-01-the-session-holds-the-whole-vault-store-to-use-five-operations) (EDITOR), [ISP-CANVAS-04](../areas/canvas.md#isp-canvas-04-canvassession-stores-the-whole-vaultstore-and-uses-four-members) (CANVAS), [ISP-BASES-01](../areas/bases.md#isp-bases-01-every-bases-entry-point-takes-the-whole-vaultstore-and-vaultindex-actors) (BASES), [ISP-READING-03](../areas/reading.md#isp-reading-03-the-builder-takes-a-whole-vaultindex-for-one-call-and-threads-five-parameters-through-every-helper) (READING).

**Evidence.**
- Both sessions declare `private let store: VaultStore` ([MarkdownSession.swift:9](../../../Sources/GraphiteUI/MarkdownSession.swift#L9), [CanvasSession.swift:68](../../../Sources/GraphiteUI/CanvasSession.swift#L68)).
- `VaultStore.swift` declares 24 public methods. Among them are `move` ([VaultStore.swift:307](../../../Sources/GraphiteCore/VaultStore.swift#L307)), `delete` ([:378](../../../Sources/GraphiteCore/VaultStore.swift#L378)), `saveSettings` ([:278](../../../Sources/GraphiteCore/VaultStore.swift#L278)) and `updateBookmarks` ([:185](../../../Sources/GraphiteCore/VaultStore.swift#L185)). Three more files extend it ([CommunityPluginInventory.swift:121](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L121), [ObsidianThemes.swift:82](../../../Sources/GraphiteCore/ObsidianThemes.swift#L82), [CommunityPluginList.swift:51](../../../Sources/GraphiteCore/CommunityPluginList.swift#L51)).
- `MarkdownSession` uses `save`, `read`, `fileExists`, `uniquePath` and `propertyTypes`. `CanvasSession` uses the first four.
- `BaseDocumentModel` uses 4 store members and 5 index members (`ISP-BASES-01`). That includes the read-only embedded base.
- `ReadingViewBuilder` takes a whole `VaultIndex` for one call (`ISP-READING-03`).

**Concrete cost.**
- By type, a note session, a canvas or an embedded read-only base can delete or move any vault item. OBJECTIVE.md's "never lose user files" then rests on discipline, not on the compiler.
- Every session test builds a real `VaultStore` over a real folder (`ISP-EDITOR-01`, `ISP-VAULT-01`).
- Failure paths such as "save throws mid-copy" stay untested, because no narrower seam exists (`ISP-CANVAS-04`).

**Shared fix direction.**
- One document-file capability serves every document session: `DocumentFileAccess` with `read`, `save(expecting:)`, `fileExists` and `uniquePath` (VAULT's name; EDITOR calls it `NoteFileStore`, CANVAS "a four-member document-file capability"). Property types are passed as a value.
- Bases gets `BaseRecordSource` (index reads) and `BaseFileAccess`.
- Each has one contract test suite, run by the real store and by a failure-injecting fake that keeps revision checks.
- Use one name: `DocumentFileAccess`.

### 2.3 Views write model state that should change only through intents

**What it is.** `@Observable` models expose plain `var`s that carry invariants or one-way decisions. Views set them directly, through gesture handlers, `Binding(get:set:)` or after reading them. Some of these fields are also used to carry an outcome from one call to a later one.

**Where it occurs.** Eight areas: [ISP-SHELL-03](../areas/shell.md#isp-shell-03-core-workspace-state-is-publicly-settable-and-tests-and-views-assign-it-directly) (SHELL), [ISP-PLUGIN-02](../areas/plugin.md#isp-plugin-02-21-host-properties-are-writable-from-outside-the-host) (PLUGIN), [ISP-CANVAS-02](../areas/canvas.md#isp-canvas-02-views-write-six-session-fields-directly-instead-of-calling-intent-methods) (CANVAS), [ISP-LECTURE-04](../areas/lecture.md#isp-lecture-04-views-write-pdfsession-state-directly-through-10-public-setters) (LECTURE), [ISP-BASES-02](../areas/bases.md#isp-bases-02-the-view-mutates-model-state-that-should-change-only-through-intents) (BASES), [ISP-READING-02](../areas/reading.md#isp-reading-02-panes-write-the-windows-read-aloud-navigator-directly-the-last-writer-wins) (READING), [ISP-VOICE-02](../areas/voice.md#isp-voice-02-views-take-the-whole-controller-and-drive-the-session-directly) (VOICE), [ISP-RUNTIME-02](../areas/runtime.md#isp-runtime-02-nine-fields-are-written-onto-objects-from-files-that-do-not-own-them) (RUNTIME, the same shape in JavaScript).

**Evidence.**
- `var folderAccess`, `var store`, `var index` and `var layout` are writable from outside `WorkspaceModel` ([WorkspaceModel.swift:12-17](../../../Sources/GraphiteUI/WorkspaceModel.swift#L12-L17), [:40](../../../Sources/GraphiteUI/WorkspaceModel.swift#L40)).
- `PDFSession.acceptsSignatureInvalidation` is a plain `var` ([PDFSession.swift:337](../../../Sources/GraphiteUI/PDFSession.swift#L337)). A button sets it ([PDFPane.swift:283](../../../Sources/GraphiteUI/PDFPane.swift#L283)). `isWriting` is set from 3 other files through bindings and closures ([DocumentModeToggle.swift:179](../../../Sources/GraphiteUI/DocumentModeToggle.swift#L179), [WorkspaceCanvas.swift:16](../../../Sources/GraphiteUI/WorkspaceCanvas.swift#L16), [PDFPane.swift:180](../../../Sources/GraphiteUI/PDFPane.swift#L180)).
- Canvas gesture handlers read, change and write back `session.viewport` ([CanvasBoardHost.swift:108-123](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L108-L123)), bypassing `stopViewportAnimation` except at `.began`.
- `BaseDocumentModel.actionErrorMessage` is a settable `var` ([BaseDocumentModel.swift:36](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L36)). The view reads and clears it to carry a save failure into a sheet ([BaseDocumentView.swift:314-317](../../../Sources/GraphiteUI/BaseDocumentView.swift#L314-L317)).
- The plugin host's `isPanelShownInline` is set by a settings page to route a later `present` call ([CommunityPluginHost.swift:278](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L278)).
- `MarkdownPane` overwrites the window's `readAloudNavigator.visibleLocation` closure ([MarkdownPane.swift:133-138](../../../Sources/GraphiteUI/MarkdownPane.swift#L133-L138)).
- Read Aloud views reach through the controller into the session on 67 lines. grep `reader\.session\.`: 21 in `ReadAloudNavigator.swift`, 15 each in `ReadAloudControls.swift`, `ReadAloudFloatingPlayer.swift` and `ReadAloudReader.swift`, and 1 in `MarkdownPane.swift`.

**Concrete cost.**
- Invariants become optional:
  - The canvas accessibility action selects a card without `endEditing()`, unlike every touch path (`ISP-CANVAS-02`).
  - The floating player's sentence buttons stay enabled while `isPreparing`, but its Play button does not ([ReadAloudFloatingPlayer.swift:213-243](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L213-L243); VOICE's correction to `ISP-VOICE-02`).
  - With two notes side by side, Read Aloud asks the pane that changed mode last where the reader is (`ISP-READING-02`).
- A one-way, destructive decision (breaking a PDF's signature) has no single method that records it (`ISP-LECTURE-04`).
- Tests can build states production never reaches, for example a `store` with no `folderAccess` (`ISP-SHELL-03`).

**Shared fix direction.**
- State with an invariant is `private(set)`. Views call named intents: `pan(by:)`, `select(node:)`, `acceptSignatureInvalidation()`, `beginWriting()`, `presentOptions(of:)`, `ReadAloudTransport.play/stop(scope:)`.
- Outcomes come back as return values (`Result<…, BaseActionError>`).
- Per-pane providers are registered by note path and removed on disappear (`visibleLocation(for:)`).
- In the runtime, classes declare their fields and take them through one method (`vault.adoptConfiguration(…)`, `hostView.attach(…)`).

### 2.4 Untyped dictionaries cross module, process and file boundaries

**What it is.** Structured data travels as `[String: Any]`, `Any` or `[String: String]`. Every reader casts with `as?` and supplies its own default, and every writer builds literals by hand.

**Where it occurs.** Seven areas: [ISP-ARCH-02](../cross-cutting/architecture.md#isp-arch-02-untyped-dictionaries-cross-the-plugin-and-diagnostics-boundaries) (ARCH), [ISP-PLUGIN-03](../areas/plugin.md#isp-plugin-03-messages-cross-the-boundary-as-string-any-with-silent-defaults) (PLUGIN), [ISP-RUNTIME-01](../areas/runtime.md#isp-runtime-01-every-message-crosses-the-boundary-as-an-untyped-dictionary-built-inline) (RUNTIME), [ISP-LECTURE-03](../areas/lecture.md#isp-lecture-03-diagnostic-payloads-are-untyped-dictionaries) (LECTURE), [ISP-VAULT-03](../areas/vault.md#isp-vault-03-untyped-string-any-crosses-the-settings-boundary) (VAULT), [ISP-MDCORE-02](../areas/mdcore.md#isp-mdcore-02-frontmatter-crosses-into-indexing-as-untyped-any) (MDCORE), [ISP-VOICE-03](../areas/voice.md#isp-voice-03-the-vault-pronunciation-file-is-decoded-as-untyped-dictionaries-and-written-through-a-narrower-type) (VOICE).

**Evidence.**
- There are 132 `[String: Any]` in production code. 46 of them are in `CommunityPluginHost.swift` ([metrics.md](../metrics.md)).
- The `views.changed` handler shows the silent defaults. A missing `placement` becomes `.tab`, a missing `isLive` becomes `false`, and a view without a title gets `""` ([CommunityPluginHost.swift:949-956](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L949-L956)).
- `DiagnosticRecords.write(kind:fields: [String: Any])` drops the whole record when one value is not JSON ([DiagnosticRecords.swift:28-37](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L28-L37)).
- `BoundedYAML.load` returns `Any?` ([MarkdownSemantics.swift:590-595](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L590-L595)).
- The pronunciation file is read as `[String: Any]` with `ipa`, then written as `[String: String]` without it ([ReadAloudPronunciations.swift:64-88](../../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L64-L88)).

**Concrete cost.**
- A misspelled key is a default value, not an error, and no test spans both sides of the runtime boundary (`ISP-RUNTIME-01`).
- The Settings editor rewrites the user's own vault file with less information (BUG-VOICE-10). That is a direct breach of OBJECTIVE.md's "the user's ordinary files are the product".
- Settings flags are read through `NSNumber` bridging, so the JSON type in the file does not decide the value read (`ISP-VAULT-03`).

**Shared fix direction.**
- Each payload gets one `Codable` type, decoded once at the edge. A decoding failure is a typed error, never a default.
- Plugin messages: one `Decodable` payload per `CommunityPluginHostOperation` case. This extends the bridge's pattern ([CommunityPluginVaultBridge.swift:82-109](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L82-L109)), and the JavaScript constant table is generated from the same enum.
- Diagnostics: `Encodable` record structs.
- YAML: a typed `YAMLValue`.
- Settings: the existing `JSONValue` enum ([Bookmarks.swift:5](../../../Sources/GraphiteCore/Bookmarks.swift#L5)).
- Pronunciations: one `Codable` entry enum used for both reading and writing.

### 2.5 Fat protocols that join unrelated concerns or read and destroy

**What it is.** One protocol or type joins concerns that different consumers use separately. Some conformers end up stubbing requirements. Read-only consumers end up holding destructive methods.

**Where it occurs.** Five areas: [ISP-VOICE-01](../areas/voice.md#isp-voice-01-readaloudspeaking-has-16-requirements-covering-6-concerns) (VOICE), [ISP-INK-01](../areas/ink.md#isp-ink-01-lassocanvascontent-is-a-10-member-protocol-whose-capture-consumer-uses-2) (INK), [ISP-VAULT-02](../areas/vault.md#isp-vault-02-conflictversionstore-joins-discovery-and-destruction-in-one-six-member-protocol) (VAULT), [ISP-LECTURE-02](../areas/lecture.md#isp-lecture-02-pdfpanehealthmonitor-receives-the-whole-coordinator-and-uses-9-of-its-members) (LECTURE, a concrete class used as the interface), [ISP-MDCORE-01](../areas/mdcore.md#isp-mdcore-01-locatedblock-has-fields-that-apply-to-one-case-each) (MDCORE, a value type whose fields each apply to one case).

**Evidence.**
- `ReadAloudSpeaking` declares 16 requirements: events, voice catalogue, permissions, playback, audio route and ahead-of-time rendering ([ReadAloudSpeech.swift:101-133](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L101-L133)). `NeuralReadAloudSpeech` forwards six catalogue and permission members to the system voice.
- `LassoCanvasContent` declares 11 requirements ([LassoTools.swift:175-203](../../../Sources/GraphiteUI/LassoTools.swift#L175-L203)). `LassoAreaCapture.image` uses `drawContentUnderInk` and `lassoDisplayQuarterTurns` only ([LassoTools.swift:229-251](../../../Sources/GraphiteUI/LassoTools.swift#L229-L251)). `SelectedPicturesContent` stubs 5 of them (`LSP-INK-02`).
- `ConflictVersionStore` puts `hasConflictVersions`, `conflictVersions` and `contentsLocation` beside `replaceFile`, `keepVersion` and `removeVersions` ([FileVersionConflicts.swift:12-31](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L12-L31)).
- `PDFPaneHealthMonitor` reaches 9 members of the 37-property `PDFAnnotationCoordinator` ([PDFPaneHealth.swift:202](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L202), [:219](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L219)).

**Concrete cost.**
- Every fake must reason about 16 members, and the forwarding layer grows with each concern (`ISP-VOICE-01`). RULES.md warns against exactly this kind of forwarding layer.
- A stub conformer silently loses editing calls (`LSP-INK-02`).
- The background discovery that scans up to 5,000 files holds a value that can remove versions (`ISP-VAULT-02`).
- The health monitor cannot be tested without the largest class in LECTURE.

**Shared fix direction.**
- Split each protocol along its consumers, and only where each part has a real substitution:
  - `ReadAloudSpeechPlayback`, `ReadAloudVoiceCatalogue` and `AheadOfTimeRendering`.
  - `LassoPictureEditing` (6 members) and `LassoCaptureSource` (5).
  - `ConflictVersionDiscovery` and `ConflictVersionResolution`.
  - A `PDFCanvasHealthPort`.
- Each split protocol gets one shared contract test that every conformer runs.
- Case-specific data moves into enum payloads (`LocatedBlock`).

### 2.6 Closure bags and settable callback slots

**What it is.** Structs of 9 to 25 closures and values are handed whole to every consumer. UIKit views expose settable closure properties that their owner fills in after construction, from several places.

**Where it occurs.** Four areas: [ISP-EDITOR-02](../areas/editor.md#isp-editor-02-editoractions-is-a-14-closure-bag-platform-forked-read-piecemeal), [ISP-EDITOR-04](../areas/editor.md#isp-editor-04-every-block-view-receives-a-25-member-environment) and [ISP-EDITOR-05](../areas/editor.md#isp-editor-05-both-text-views-expose-12-to-14-mutable-closure-slots-set-from-outside) (EDITOR), [ISP-SHELL-04](../areas/shell.md#isp-shell-04-windowactions-carries-10-closures-to-every-command-consumer) (SHELL), [ISP-BASES-03](../areas/bases.md#isp-bases-03-baseviewactions-is-a-nine-member-bag-handed-to-every-cell) (BASES), [ISP-INK-02](../areas/ink.md#isp-ink-02-infinitecanvasview-exposes-ten-settable-callbacks-and-configuration-fields-for-its-one-owner) (INK).

**Evidence.**
- `EditorActions` has 13 shared optional members plus one per platform. One of them, `quickFontSize`, is a value, not a closure ([EditorKeyboardToolbar.swift:31-68](../../../Sources/GraphiteUI/EditorKeyboardToolbar.swift#L31-L68)).
- `LivePreviewEnvironment` has 25 members ([LivePreviewWidgets.swift:37-82](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L37-L82)).
- `WindowActions` has 10 ([WorkspaceCommands.swift:5-19](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L5-L19)) and `BaseViewActions` 9 ([BaseValueViews.swift:12-26](../../../Sources/GraphiteUI/BaseValueViews.swift#L12-L26)).
- `InfiniteCanvasView` has 10 settable callback and configuration fields ([DrawingEditor.swift:824-838](../../../Sources/GraphiteUI/DrawingEditor.swift#L824-L838)).
- The iPad `MarkdownTextView` has settable slots such as `reportReadingHighlightFrame`, `didLayout` and `didMoveIntoWindow` ([NativeMarkdownEditor.swift:25](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L25), [:41-42](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L41-L42)). They are assigned in three places.

**Concrete cost.**
- An optional closure means both "feature available" and "action", so a forgotten closure looks like a disabled feature and the compiler never complains (`ISP-EDITOR-02`, `ISP-INK-02`).
- A new field in `LivePreviewEnvironment` must be remembered in a hand-written string signature, or blocks show stale state (`ISP-EDITOR-04`).
- A retained text view resumed in a new container keeps the closures from its first configuration (`ISP-EDITOR-05`).
- Dead members pile up: `EditorKeyboardToolbar.update(actions:)` is never called.

**Shared fix direction.**
- Group closures by consumer: `AttachmentActions`, `LinkFollowing`, `PluginEditorHooks`, `BaseNavigationActions` and `BaseCellEditing`.
- Availability is a `Set<EditorFeature>`, not optional closures.
- Appearance becomes an `Equatable` value (`BlockAppearance`), which replaces the string signature.
- A UIKit view talks to its single owner through one weak owner reference with methods (`MarkdownTextViewHost`, `DrawingPictureEvents`). Construction-time values go into the initializer.

## 3. Largest offenders

The rows are ranked by reach (how many consumers receive the interface) times excess (members received but not used).

| # | Type or interface | Numbers | Findings |
| ---: | --- | --- | --- |
| 1 | `WorkspaceModel` passed as a consumer's interface | 86 stored properties. 69 consumer stored declarations in 23 files plus 17 function parameters. Leaf views use 1 (`VaultItemDragPreview`), 2 (`SearchResultRow`, `ConflictVersionsBanner`) or 7 (`TabSwitcher`) members. | ISP-ARCH-01, ISP-SHELL-01 |
| 2 | `CommunityPluginHost` ↔ `WorkspaceModel` | The host reaches 23 workspace members, including `move` and `store` (which it uses to `delete`). About 20 declarations hold the whole host, including `LivePreviewEnvironment.pluginCodeBlocks`. 21 properties are writable from outside, and the host's surface has 63 properties. | ISP-SHELL-02, ISP-PLUGIN-01, ISP-PLUGIN-02 |
| 3 | `MarkdownPane` (and `NoteLinksInspector`) | Uses 38 workspace members and writes 6 workspace fields. Overwrites the window-wide `readAloudNavigator.visibleLocation`. | ISP-READING-01, ISP-READING-02 |
| 4 | `VaultStore` as a session dependency | 24 public methods in the main file plus extensions in 3 files. Stored or passed in 11 files (27 lines). `MarkdownSession` uses 5, `CanvasSession` 4 and `BaseDocumentModel` 4 (plus 5 of `VaultIndex`). | ISP-VAULT-01, ISP-EDITOR-01, ISP-CANVAS-04, ISP-BASES-01 |
| 5 | `CanvasPane` / `CanvasFilePicker` | Uses 20 workspace members and writes `viewedImageNote`, `viewedImage` and `errorMessage`. The canvas views write 6 session fields directly. | ISP-CANVAS-01, ISP-CANVAS-02 |
| 6 | Plugin ↔ runtime message boundary | 96 lines with `[String: Any]` in PLUGIN scope (46 occurrences in the host file). Every runtime payload is an inline literal. 132 `[String: Any]` in production code overall. | ISP-PLUGIN-03, ISP-RUNTIME-01, ISP-ARCH-02 |
| 7 | `ReadAloudSpeaking` and the Read Aloud controller | 16 requirements covering 6 concerns, 6 of them forwarded by the neural adapter. 67 view lines reach `reader.session.` past the controller. | ISP-VOICE-01, ISP-VOICE-02 |
| 8 | `PDFSession` / `PDFAnnotationCoordinator` | 10 session fields set by views, including the one-way `acceptsSignatureInvalidation`. The health monitor uses 9 members of the 37-property coordinator. | ISP-LECTURE-04, ISP-LECTURE-02 |
| 9 | Editor closure surfaces | `EditorActions` has 13 members per platform, `LivePreviewEnvironment` 25 (passed to every block), and the text views 12 (iPad) and 14 (Mac) settable closure slots, assigned in 3 places. `CompletionProvider` holds the workspace for 9 members. | ISP-EDITOR-02, ISP-EDITOR-04, ISP-EDITOR-05, ISP-EDITOR-03 |
| 10 | `LassoCanvasContent` | 11 requirements. The capture consumer uses 2. `SelectedPicturesContent` stubs 5. There are 2 production conformers and no shared contract test. | ISP-INK-01 |

## 4. What to keep for this principle

These designs already meet the principle. The cleanup must copy them and must not undo them.

| Design | Evidence | Why it is the model |
| --- | --- | --- |
| Narrow editor ports with two real implementations each | `MarkdownStyledTextView`, 5 members ([MarkdownEditorStyling.swift:12-22](../../../Sources/GraphiteUI/MarkdownEditorStyling.swift#L12-L22)). `RetainableMarkdownEditor`, 3 members ([MarkdownEditorRetention.swift:10-18](../../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L10-L18)). | One shared styling engine serves `UITextView` and `NSTextView` through the 5-member port. Retention has a test fake. This is exactly the protocol use RULES.md allows (EDITOR section 6). |
| Lookup protocol with an in-memory implementation that follows the production rules | `BaseRecordProvider`, 3 requirements, with its contract stated on the protocol ([BaseFileRecord.swift:234-241](../../../Sources/GraphiteCore/BaseFileRecord.swift#L234-L241)). `BaseInMemoryRecordProvider` ([:246](../../../Sources/GraphiteCore/BaseFileRecord.swift#L246)). | The evaluator depends only on what it uses. Tests run without an index (BASES verdict). |
| Two-requirement canvas provider | `PDFInkCanvasProvider` ([PDFEditHistory.swift:78-83](../../../Sources/GraphiteUI/PDFEditHistory.swift#L78-L83)) | The history needs a canvas for a page and whether the page is shown, nothing more (LECTURE verdict). |
| Capture seam that drives the production writer | `VideoCaptureSource` ([VideoCapture.swift:89-100](../../../Sources/GraphiteApple/VideoCapture.swift#L89-L100)). `RecordingStorage` ([VideoRecording.swift:8](../../../Sources/GraphiteApple/VideoRecording.swift#L8)). | A synthetic source exercises the real movie writer (LECTURE, "What to keep"). |
| Rendering and alignment seams with a stated reason | `NeuralPassageRendering` ([ReadAloudPassagePreparation.swift:8](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L8)), `ReadAloudSpeechAligning` ([ReadAloudSpeechAlignment.swift:8](../../../Sources/GraphiteVoices/ReadAloudSpeechAlignment.swift#L8)) | Each exists because tests cannot load a multi-hundred-megabyte model. One production implementation each (VOICE section 6, row 13). |
| Views that take values and closures, not models | `PropertiesPanel(properties:update:follow:)` ([PropertiesPanel.swift:8-15](../../../Sources/GraphiteUI/PropertiesPanel.swift#L8-L15)). `ReadingTaskContext` with one `toggle` closure ([ReadingTaskCheckbox.swift:6-13](../../../Sources/GraphiteUI/ReadingTaskCheckbox.swift#L6-L13)). `ReadingImageActions` with identity-based equality ([MarkdownPreview.swift:2964-2977](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2964-L2977)). | READING names these as the shape `MarkdownPane` must take. The equality rule keeps redraws bounded. |
| Typed decoding at a boundary | The bridge decodes requests into private `Decodable` structs and answers `{failure: {kind, message}}` ([CommunityPluginVaultBridge.swift:34-44](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L34-L44), [:82-109](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L82-L109)). | A malformed message is `invalidData`, never a default. `ISP-PLUGIN-03` and `ISP-RUNTIME-01` extend this pattern to every operation. |
| One injected transport in the runtime | `hostBridge` replaced by the Node harness ([community-plugin-runtime-foundation.js:30-49](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L30-L49)) | Tests run the production scripts against a fake host (RUNTIME section 6, row 6). |
| Typed JSON value | `JSONValue` ([Bookmarks.swift:5](../../../Sources/GraphiteCore/Bookmarks.swift#L5)) | Keeps unknown fields and whole numbers whole. It is the replacement for `[String: Any]` in settings (`ISP-VAULT-03`). |
| Core as functions from values to values | `MarkdownEditing` commands return one `MarkdownTextEdit` ([MarkdownEditing.swift:3-14](../../../Sources/GraphiteCore/MarkdownEditing.swift#L3-L14)). | Consumers receive exactly the value they asked for. MDCORE is "Mostly strong" because of this. |
| A feature model behind an injected seam | Conflict versions: model, wording enum, injected `ConflictVersionStore` ([ConflictVersionsSheet.swift:8-65](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L8-L65), [WorkspaceModel.swift:165](../../../Sources/GraphiteUI/WorkspaceModel.swift#L165)) | SHELL calls it "already the target shape". Split the protocol per `ISP-VAULT-02`, and keep the feature model and the seam. |
| Value types that views can take directly | `TabLayout` ([WorkspaceTabs.swift:84-216](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L84-L216) delegates every decision to it), `WorkspaceFocusMode` | A view that takes `TabLayout` plus intents needs no workspace (fix for `ISP-SHELL-01`). |
| Intent methods with validated state | `PencilToolbox` ([PencilToolbox.swift:128-143](../../../Sources/GraphiteUI/PencilToolbox.swift#L128-L143)) | Views change tools only through intents, and stored values are clamped. This is the model for `PDFSession`, `CanvasSession` and `BaseDocumentModel` (pattern 2.3). |

## 5. Index of findings

Taken from [findings-index.md](../findings-index.md): 40 findings, ordered by severity and then by ID.

| ID | Area | Severity | Title |
| --- | --- | --- | --- |
| [ISP-ARCH-01](../cross-cutting/architecture.md#isp-arch-01-74-declarations-take-the-whole-workspacemodel-to-use-a-few-members) | ARCH | High | 74 declarations take the whole `WorkspaceModel` to use a few members |
| [ISP-PLUGIN-01](../areas/plugin.md#isp-plugin-01-the-host-takes-the-whole-workspace-and-views-take-the-whole-host) | PLUGIN | High | The host takes the whole workspace, and views take the whole host |
| [ISP-SHELL-01](../areas/shell.md#isp-shell-01-51-view-declarations-in-scope-take-the-whole-workspacemodel-to-use-one-to-seven-members) | SHELL | High | 51 view declarations in scope take the whole `WorkspaceModel` to use one to seven members |
| [ISP-BASES-01](../areas/bases.md#isp-bases-01-every-bases-entry-point-takes-the-whole-vaultstore-and-vaultindex-actors) | BASES | Medium | Every Bases entry point takes the whole `VaultStore` and `VaultIndex` actors |
| [ISP-BASES-02](../areas/bases.md#isp-bases-02-the-view-mutates-model-state-that-should-change-only-through-intents) | BASES | Medium | The view mutates model state that should change only through intents |
| [ISP-CANVAS-01](../areas/canvas.md#isp-canvas-01-canvaspane-and-canvasfilepicker-take-the-whole-workspacemodel-for-about-20-members) | CANVAS | Medium | `CanvasPane` and `CanvasFilePicker` take the whole `WorkspaceModel` for about 20 members |
| [ISP-CANVAS-02](../areas/canvas.md#isp-canvas-02-views-write-six-session-fields-directly-instead-of-calling-intent-methods) | CANVAS | Medium | Views write six session fields directly instead of calling intent methods |
| [ISP-EDITOR-01](../areas/editor.md#isp-editor-01-the-session-holds-the-whole-vault-store-to-use-five-operations) | EDITOR | Medium | The session holds the whole vault store to use five operations |
| [ISP-EDITOR-02](../areas/editor.md#isp-editor-02-editoractions-is-a-14-closure-bag-platform-forked-read-piecemeal) | EDITOR | Medium | `EditorActions` is a 14-closure bag, platform-forked, read piecemeal |
| [ISP-INK-01](../areas/ink.md#isp-ink-01-lassocanvascontent-is-a-10-member-protocol-whose-capture-consumer-uses-2) | INK | Medium | `LassoCanvasContent` is a 10-member protocol whose capture consumer uses 2 |
| [ISP-LECTURE-04](../areas/lecture.md#isp-lecture-04-views-write-pdfsession-state-directly-through-10-public-setters) | LECTURE | Medium | Views write `PDFSession` state directly through 10 public setters |
| [ISP-PLUGIN-02](../areas/plugin.md#isp-plugin-02-21-host-properties-are-writable-from-outside-the-host) | PLUGIN | Medium | 21 host properties are writable from outside the host |
| [ISP-PLUGIN-03](../areas/plugin.md#isp-plugin-03-messages-cross-the-boundary-as-string-any-with-silent-defaults) | PLUGIN | Medium | Messages cross the boundary as `[String: Any]` with silent defaults |
| [ISP-READING-01](../areas/reading.md#isp-reading-01-the-note-pane-and-the-inspector-take-the-whole-workspacemodel) | READING | Medium | The note pane and the inspector take the whole `WorkspaceModel` |
| [ISP-READING-02](../areas/reading.md#isp-reading-02-panes-write-the-windows-read-aloud-navigator-directly-the-last-writer-wins) | READING | Medium | Panes write the window's Read Aloud navigator directly; the last writer wins |
| [ISP-RUNTIME-01](../areas/runtime.md#isp-runtime-01-every-message-crosses-the-boundary-as-an-untyped-dictionary-built-inline) | RUNTIME | Medium | Every message crosses the boundary as an untyped dictionary built inline |
| [ISP-RUNTIME-02](../areas/runtime.md#isp-runtime-02-nine-fields-are-written-onto-objects-from-files-that-do-not-own-them) | RUNTIME | Medium | Nine fields are written onto objects from files that do not own them |
| [ISP-SHELL-02](../areas/shell.md#isp-shell-02-communitypluginhost-and-workspacemodel-reference-each-other-the-host-reads-about-23-workspace-members) | SHELL | Medium | `CommunityPluginHost` and `WorkspaceModel` reference each other; the host reads about 23 workspace members |
| [ISP-SHELL-03](../areas/shell.md#isp-shell-03-core-workspace-state-is-publicly-settable-and-tests-and-views-assign-it-directly) | SHELL | Medium | Core workspace state is publicly settable, and tests and views assign it directly |
| [ISP-VAULT-01](../areas/vault.md#isp-vault-01-consumers-that-need-four-or-five-file-operations-receive-all-32-vaultstore-methods) | VAULT | Medium | Consumers that need four or five file operations receive all 32 `VaultStore` methods |
| [ISP-VOICE-01](../areas/voice.md#isp-voice-01-readaloudspeaking-has-16-requirements-covering-6-concerns) | VOICE | Medium | `ReadAloudSpeaking` has 16 requirements covering 6 concerns |
| [ISP-VOICE-02](../areas/voice.md#isp-voice-02-views-take-the-whole-controller-and-drive-the-session-directly) | VOICE | Medium | Views take the whole controller and drive the session directly |
| [ISP-VOICE-03](../areas/voice.md#isp-voice-03-the-vault-pronunciation-file-is-decoded-as-untyped-dictionaries-and-written-through-a-narrower-type) | VOICE | Medium | The vault pronunciation file is decoded as untyped dictionaries and written through a narrower type |
| [ISP-ARCH-02](../cross-cutting/architecture.md#isp-arch-02-untyped-dictionaries-cross-the-plugin-and-diagnostics-boundaries) | ARCH | Low | Untyped dictionaries cross the plugin and diagnostics boundaries |
| [ISP-BASES-03](../areas/bases.md#isp-bases-03-baseviewactions-is-a-nine-member-bag-handed-to-every-cell) | BASES | Low | `BaseViewActions` is a nine-member bag handed to every cell |
| [ISP-CANVAS-03](../areas/canvas.md#isp-canvas-03-the-local-graph-and-map-panels-take-a-markdownsession-to-read-its-path) | CANVAS | Low | The local graph and map panels take a `MarkdownSession` to read its path |
| [ISP-CANVAS-04](../areas/canvas.md#isp-canvas-04-canvassession-stores-the-whole-vaultstore-and-uses-four-members) | CANVAS | Low | `CanvasSession` stores the whole `VaultStore` and uses four members |
| [ISP-EDITOR-03](../areas/editor.md#isp-editor-03-suggestions-take-the-whole-workspace) | EDITOR | Low | Suggestions take the whole workspace |
| [ISP-EDITOR-04](../areas/editor.md#isp-editor-04-every-block-view-receives-a-25-member-environment) | EDITOR | Low | Every block view receives a 25-member environment |
| [ISP-EDITOR-05](../areas/editor.md#isp-editor-05-both-text-views-expose-12-to-14-mutable-closure-slots-set-from-outside) | EDITOR | Low | Both text views expose 12 to 14 mutable closure slots set from outside |
| [ISP-INK-02](../areas/ink.md#isp-ink-02-infinitecanvasview-exposes-ten-settable-callbacks-and-configuration-fields-for-its-one-owner) | INK | Low | `InfiniteCanvasView` exposes ten settable callbacks and configuration fields for its one owner |
| [ISP-LECTURE-01](../areas/lecture.md#isp-lecture-01-recording-views-take-the-whole-workspacemodel-to-use-five-members) | LECTURE | Low | Recording views take the whole `WorkspaceModel` to use five members |
| [ISP-LECTURE-02](../areas/lecture.md#isp-lecture-02-pdfpanehealthmonitor-receives-the-whole-coordinator-and-uses-9-of-its-members) | LECTURE | Low | `PDFPaneHealthMonitor` receives the whole coordinator and uses 9 of its members |
| [ISP-LECTURE-03](../areas/lecture.md#isp-lecture-03-diagnostic-payloads-are-untyped-dictionaries) | LECTURE | Low | Diagnostic payloads are untyped dictionaries |
| [ISP-MDCORE-01](../areas/mdcore.md#isp-mdcore-01-locatedblock-has-fields-that-apply-to-one-case-each) | MDCORE | Low | `LocatedBlock` has fields that apply to one case each |
| [ISP-MDCORE-02](../areas/mdcore.md#isp-mdcore-02-frontmatter-crosses-into-indexing-as-untyped-any) | MDCORE | Low | Frontmatter crosses into indexing as untyped `Any` |
| [ISP-READING-03](../areas/reading.md#isp-reading-03-the-builder-takes-a-whole-vaultindex-for-one-call-and-threads-five-parameters-through-every-helper) | READING | Low | The builder takes a whole `VaultIndex` for one call and threads five parameters through every helper |
| [ISP-SHELL-04](../areas/shell.md#isp-shell-04-windowactions-carries-10-closures-to-every-command-consumer) | SHELL | Low | `WindowActions` carries 10 closures to every command consumer |
| [ISP-VAULT-02](../areas/vault.md#isp-vault-02-conflictversionstore-joins-discovery-and-destruction-in-one-six-member-protocol) | VAULT | Low | `ConflictVersionStore` joins discovery and destruction in one six-member protocol |
| [ISP-VAULT-03](../areas/vault.md#isp-vault-03-untyped-string-any-crosses-the-settings-boundary) | VAULT | Low | Untyped `[String: Any]` crosses the settings boundary |

Totals: 3 High, 20 Medium, 17 Low, 40 in all. These match the ISP row of [findings-index.md](../findings-index.md).

## 6. Rules for new code

These rules adapt the starting set's interface rules to Swift and SwiftUI: "no consumer takes the application root", "capability interfaces have at most ~7 members", "no untyped dictionaries across module boundaries", "outcomes travel as return values", and "shared contract tests per interface". Each rule must be checkable in review or by a script. RULES.md's warning applies throughout: a protocol is added only for a real substitution, test or isolation need. A struct of closures or a narrow `@Observable` model is the default capability shape.

**ISP 1. No consumer holds the application root.**
- Rule: Only the composition root and the scene that owns `WorkspaceModel` (or its successor `Workspace`) may store a reference to it. No view, model, service or function parameter may take it.
- Check: `grep -rnE '(let|var) \w+: WorkspaceModel|: WorkspaceModel[,)]' Sources/` may only return allow-listed files. CI fails when the count rises above today's baseline (69 consumer stored declarations, 17 parameters) and the baseline only goes down.
- Answers: ISP-ARCH-01, ISP-SHELL-01, ISP-READING-01, ISP-CANVAS-01, ISP-LECTURE-01, ISP-EDITOR-03.

**ISP 2. Leaf views take values and intent closures; container views take the one narrow model they show.**
- Rule: A row, preview, banner or panel takes values (`VaultEntry`, `VaultPath`, `TabLayout`, `String`) plus closures for its intents. A container takes at most one `@Observable` feature model (for example `TabWorkspace`). A view never takes a session to read one property.
- Check: in review, every stored property of a `View` that is a class type is either the single feature model or justified in its doc comment. Views named `*Row`, `*Preview` or `*Banner` have no class-typed stored property.
- Answers: ISP-SHELL-01, ISP-CANVAS-03, ISP-READING-01, ISP-LECTURE-01.

**ISP 3. No back-references from a service to its owner.**
- Rule: A long-lived service (the plugin host, a health monitor, a completion provider) must not hold a `weak var` to the workspace or to a coordinator. It receives a capability value or protocol, owned by the service's module, with at most 7 members.
- Check: `grep -nE 'weak var \w+: (WorkspaceModel|PDFAnnotationCoordinator)'` returns nothing. A capability type with more than 7 members has a doc comment that names its consumers.
- Answers: ISP-SHELL-02, ISP-PLUGIN-01, ISP-LECTURE-02, ISP-EDITOR-03.

**ISP 4. At most 7 members per capability, split by consumer.**
- Rule: A protocol, a struct of closures or an environment value has at most 7 members. If two consumers use disjoint subsets, the interface must be split along those subsets, even when it is under 7.
- Check: a script counts requirements of `protocol` declarations and stored properties of types named `*Actions`, `*Environment` or `*Context`, and fails above 7 unless an allow-list entry links a design note. In review, ask "which consumer uses which members".
- Answers: ISP-VOICE-01, ISP-INK-01, ISP-EDITOR-02, ISP-EDITOR-04, ISP-SHELL-04, ISP-BASES-03.

**ISP 5. Reading and destroying are separate capabilities.**
- Rule: A consumer that only lists, reads or discovers must receive an interface without `delete`, `move`, `remove*`, `replace*` or `save*` members. Destructive members live in a separate interface, given only to the workflow that performs the destruction.
- Check: a protocol or capability struct that has both read members and members named `delete|move|remove|replace|save` is flagged in review. Read-only consumers (embedded bases, discovery scans) are checked for the type they receive.
- Answers: ISP-VAULT-02, ISP-VAULT-01, ISP-BASES-01.

**ISP 6. Sessions depend on `DocumentFileAccess`, not on `VaultStore` or `VaultIndex`.**
- Rule: Document sessions (`MarkdownSession`, `CanvasSession`, `PDFSession`, `BaseDocumentModel`) and builders must take the document-file capability (`read`, `save(expecting:)`, `fileExists`, `uniquePath`) and, where needed, a feature-owned index capability (`BaseRecordSource`, `ReadingFileLookup`). Never the actors themselves.
- Check: `grep -nE ': (VaultStore|VaultIndex)\b' Sources/GraphiteUI` only matches the composition root and the vault module's own files.
- Answers: ISP-VAULT-01, ISP-EDITOR-01, ISP-CANVAS-04, ISP-BASES-01, ISP-READING-03.

**ISP 7. Model state with an invariant is `private(set)`; views call intents.**
- Rule: In an `@Observable` model, every stored property that an invariant, a one-way decision or an ordering rule depends on must be `private(set)`. Views change it only through named intent methods. A `Binding(get:set:)` may call an intent but must not assign a model field.
- Check: `grep -nE '(session|model|host|workspace)\.\w+ = ' Sources/GraphiteUI/*View*.swift Sources/GraphiteUI/*Pane*.swift` returns no assignments. In review, every non-`private(set)` `var` on an `@Observable` model has a doc comment saying why a view may write it.
- Answers: ISP-SHELL-03, ISP-PLUGIN-02, ISP-CANVAS-02, ISP-LECTURE-04, ISP-BASES-02, ISP-VOICE-02.

**ISP 8. Views talk to the controller, never to the controller's parts.**
- Rule: A view receives the transport or status projection it shows (`ReadAloudTransport`, `ReadAloudStatus`). It must not reach through a controller into its session (`reader.session.play()`).
- Check: grep for chained model access `\w+\.session\.\w+\(` in view files returns nothing (today: 67 lines of `reader\.session\.`, a baseline that only goes down).
- Answers: ISP-VOICE-02, ISP-LECTURE-02.

**ISP 9. An outcome is a return value, not a field a later caller reads and clears.**
- Rule: An intent that can fail or route a follow-up returns `Result<…, TypedError>` or the routing value. It must not leave the outcome in a shared field such as `actionErrorMessage` or `isPanelShownInline` for a view to take.
- Check: in review, look for a view that writes `nil` to a model's message or flag after reading it (`takeActionErrorMessage`). Such a pair is rejected.
- Answers: ISP-BASES-02, ISP-PLUGIN-02.

**ISP 10. Window-wide services take registrations keyed by identity.**
- Rule: A service shared by several panes (Read Aloud navigator, find, highlight reporting) must accept per-note or per-pane registrations that are removed on disappear. It must not expose one settable closure slot that the last writer owns.
- Check: no view assigns a closure to another object's property (`grep -nE '\.\w+ = \{'` in view files). Each `register` call has a matching unregister in `.onDisappear` or `deinit`.
- Answers: ISP-READING-02, ISP-EDITOR-05.

**ISP 11. A UIKit or AppKit view talks to its owner through one weak owner reference.**
- Rule: A platform view subclass must not expose settable closure properties for its owner to fill in after construction. It holds one `weak var owner: SomeOwnerInterface?` with methods. Configuration values go into the initializer.
- Check: `grep -nE 'var \w+: \(\(.*\) -> .*\)\?' ` over `UIView` or `NSView` subclasses returns nothing new. Baseline: 12 (iPad text view), 14 (Mac text view) and 10 (`InfiniteCanvasView`).
- Answers: ISP-EDITOR-05, ISP-INK-02.

**ISP 12. Availability is data, not an optional closure.**
- Rule: Whether a feature is offered must be expressed as a value (`Set<EditorFeature>`, an optional narrow capability). It must not be an optional closure that means both "available" and "action".
- Check: in review, a struct of more than 3 optional closures is rejected. Toolbars and menus read availability from the set.
- Answers: ISP-EDITOR-02, ISP-INK-02.

**ISP 13. No untyped dictionaries across a module, process, script or file boundary.**
- Rule: Structured data crossing between modules, to or from WebKit, into diagnostics, or to and from a vault file must be a `Codable` type, decoded once at the edge. A missing or misnamed field is a typed decoding error, never a default value. `Any` must not be returned from a parser.
- Check: CI counts `\[String\s*:\s*Any\??\]` and `-> Any\??` in `Sources/`. The count (132 today) only goes down. `as? String ?? ""` and `?? .tab`-style defaults on message fields are rejected in review.
- Answers: ISP-ARCH-02, ISP-PLUGIN-03, ISP-RUNTIME-01, ISP-LECTURE-03, ISP-VAULT-03, ISP-MDCORE-02.

**ISP 14. A file is read and written through the same type.**
- Rule: Every user-visible file Graphite rewrites (pronunciations, `types.json`, templates and daily-note settings) must have one `Codable` type used for both decode and encode. The writer must never be narrower than the reader. Each such type needs a golden round-trip test that preserves every field.
- Check: in review, a `vault*Data(for:)` writer whose input type differs from the reader's output type is rejected. A round-trip test exists for each file.
- Answers: ISP-VOICE-03, ISP-VAULT-03.

**ISP 15. A value type's fields apply to all its cases.**
- Rule: When a struct field is meaningful for only one kind of value, that data must move into the payload of an enum case. No field may be documented as "only for X".
- Check: in review, look for doc comments matching `only|1 for|other than` on stored properties of structs that sit beside a kind enum.
- Answers: ISP-MDCORE-01.

**ISP 16. Every split interface gets a shared contract test, and no conformer stubs a requirement.**
- Rule: A protocol introduced or split under these rules must have one parameterised contract test suite that every conformer runs: production, fake and in-memory. A conformer must not implement a requirement as a no-op or a sentinel value. If it would, the protocol is split instead.
- Check: for each protocol with two or more conformers, a `*ContractTests` suite exists. A script flags conformances whose method bodies are empty or return `.infinite`/`nil` constants.
- Answers: ISP-INK-01, ISP-VOICE-01, ISP-VAULT-02, ISP-CANVAS-04.

**ISP 17. Shared parameters travel as one context value.**
- Rule: When three or more helpers of one type all take the same four or more parameters, those parameters must become one context value stored on the type (for example the builder's `BuildState`). Signatures then stay at 6 parameters or fewer.
- Check: SwiftLint `function_parameter_count` with a limit of 6. In review, the same parameter list repeated in sibling helpers is rejected.
- Answers: ISP-READING-03.

**ISP 18. Runtime objects own their fields.**
- Rule: In the plugin runtime's JavaScript, a class must declare every field in its constructor. Other files may change a field only through a method of that class (`adoptConfiguration`, `attach`).
- Check: an ESLint rule (or grep `\.\(configuration\|appearanceConfiguration\|hasBeenShown\|isProbe\|waitingPlace\|lastOpenFiles\) =`) finds assignments outside the owning file and fails.
- Answers: ISP-RUNTIME-02.

## 7. Corrections

| # | Disagreement | Snapshot reading | Verdict |
| ---: | --- | --- | --- |
| 1 | ARCH (`ISP-ARCH-01`) counts 74 declarations taking `WorkspaceModel` in 27 files. SHELL (`ISP-SHELL-01`) counts 70 in 23 files. | grep `(let|var) workspace: WorkspaceModel` over `Sources/**` returns 70 lines in 23 files. ARCH's own pattern adds `weak var` and `@Bindable var`, which this grep already matches. One of the 70 is the owner ([GraphiteMacScenes.swift:9](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L9)), not a consumer. Function parameters typed `WorkspaceModel` are another 17 in 7 files, initializers excluded. | SHELL's figure is right. This document uses 69 consumer stored declarations plus 17 parameters. |
| 2 | SHELL (`ISP-SHELL-02`) says the host reads "about 23" workspace members, but lists 24. PLUGIN (`ISP-PLUGIN-01`) says 24. | grep `workspace\??\.[a-zA-Z]+` over the host's own files (`CommunityPluginHost`, `Themes`, `Typing`, `ReadingBlocks`, `Views`) gives 23 distinct members. The 24th, `scheduleThemeRefresh`, is called by the view `CommunityPluginPresentation` through its own `@Bindable var workspace` ([CommunityPluginPresentation.swift:206](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L206), [:241-246](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L241-L246)), not through the host's back-reference. | 23 through the back-reference. Both findings stand, and the number is 23. |
| 3 | INK (`ISP-INK-01`, the INK verdict row) calls `LassoCanvasContent` a 10-member protocol. Its own fix splits it into 6 + 5 members. | [LassoTools.swift:175-203](../../../Sources/GraphiteUI/LassoTools.swift#L175-L203) declares 11 requirements: `lassoPictures`, `lassoPictureImage`, `moveLassoPictures`, `deleteLassoPictures`, `setLassoPicturesHidden`, `drawContentUnderInk`, `lassoDisplayQuarterTurns`, `lassoDrawingBounds`, `lassoCaptureName`, `lassoNoteDestination`, `pastePicture`. | 11. The fix direction (6 + 5) is right, and the title's count is one short. |
| 4 | EDITOR (`ISP-EDITOR-01`) says `VaultStore` declares 26 functions. VAULT (`ISP-VAULT-01`, verdict row) says 24 public methods plus 8 in 3 extension files, 32 in all. | `VaultStore.swift` declares 24 `public func`, 2 internal (`configurationData`, `saveConfiguration`) and 4 private, nested helpers excluded. Extensions sit in [CommunityPluginInventory.swift:121](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L121), [ObsidianThemes.swift:82](../../../Sources/GraphiteCore/ObsidianThemes.swift#L82) and [CommunityPluginList.swift:51](../../../Sources/GraphiteCore/CommunityPluginList.swift#L51). | No real conflict: EDITOR counts public plus internal in the main file (26), VAULT counts the public surface across files. This document cites "24 public methods in the main file plus extensions in 3 files". |
| 5 | EDITOR (`ISP-EDITOR-02`) calls `EditorActions` a 14-closure bag. | [EditorKeyboardToolbar.swift:31-68](../../../Sources/GraphiteUI/EditorKeyboardToolbar.swift#L31-L68): 13 shared optional members plus one per platform, so 14 members per platform. One of them, `quickFontSize`, is a `QuickFontSizeAdjustment` struct ([QuickFontSizeGestures.swift:12](../../../Sources/GraphiteUI/QuickFontSizeGestures.swift#L12)), not a closure. | 14 members per platform, 13 of them closures. The finding stands. |
| 6 | VOICE (`ISP-VOICE-02`) first cites the Transcript rows as starting playback without the `isPreparing` guard. VOICE's own "Correction to an earlier section" moves the evidence to the floating player. | The Transcript sheet shows a progress view instead of the rows while preparing. The floating player's sentence buttons stay enabled while `isPreparing`, and its Play button is disabled ([ReadAloudFloatingPlayer.swift:213-243](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L213-L243)). | VOICE's correction is right. This document cites the floating player. |
