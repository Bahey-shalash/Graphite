# Community plugins: Swift host, installer, bridge, themes (PLUGIN)
Snapshot: b13dec3 (main, 2026-10-18).
Scope: `Sources/GraphiteApple/CommunityPluginSecretStore.swift`, 11 files in `Sources/GraphiteCore` (community plugin model, installer, inventory, list, manifest, network request, vault bridge, editor change, accent legibility, Obsidian appearance, themes, theme tokens), 14 files in `Sources/GraphiteUI` (plugin host and its extensions, presentation, reading blocks, settings, themes, typing, views, web content, theme resolver, theme settings, workspace appearance and theme, Graphite theme), and `Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js`; 27 files, 6,665 physical lines, 4,968 code lines (method: blank and comment-only lines and string contents removed by the reconnaissance script).

| Principle | Verdict | Reason |
| --- | --- | --- |
| S | Weak | `CommunityPluginHost` holds 63 stored properties and about 88 members over 6 files, with 12 responsibilities (counted by reading); `stopRuntime` resets 35 fields by hand and misses 13. |
| O | Weak | 44 JavaScript→Swift and 39 Swift→JavaScript operation names are string literals in 3 Swift switches and 9 runtime JavaScript files; an unknown operation from the runtime is answered as a success. |
| L | Mixed | The vault bridge's request decoding and failure answers are sound, but the Node test host disagrees with production in 7 behaviours (one hides BUG-PLUGIN-03), and 7 reads turn a failure into an empty result. |
| I | Weak | The host takes the whole `WorkspaceModel` (24 members used) and 20 types take the whole host; 21 host properties are writable from outside; 96 lines in scope carry `[String: Any]`. |
| D | Mixed | Core types receive their store, session and deletion policy; the host constructs its monitor, store, bridge, keychain store and web views, and reads `UserDefaults.standard` 3 times; 3 `URLSession = .shared` defaults; views construct installers. |
| Clean code | Mixed | 6 functions over 40 code lines, 4 sleep-polling loops, 3 hand-made "first outcome wins" primitives, 251 lines of JavaScript and 28 of HTML/CSS inside Swift strings, error kinds classified by message text; most comments state current rules well. |

## 1. Summary

**What the area does.** It installs Obsidian community plugins and themes into the vault's `.obsidian` folder, lists them, and runs enabled plugins in one `WKWebView` per vault. The Swift side is three layers:

- **Core value types and policies** (GraphiteCore): the manifest and version order ([CommunityPluginManifest.swift:6-111](../../../Sources/GraphiteCore/CommunityPluginManifest.swift#L6-L111)), the enabled list `community-plugins.json` ([CommunityPluginList.swift:6-78](../../../Sources/GraphiteCore/CommunityPluginList.swift#L6-L78)), the inventory and compatibility assessment ([CommunityPluginInventory.swift:5-158](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L5-L158)), the installers ([CommunityPluginInstaller.swift:40-171](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L40-L171), [ObsidianThemes.swift:123-194](../../../Sources/GraphiteCore/ObsidianThemes.swift#L123-L194)), the vault bridge answering `vault.*` messages through `VaultStore` ([CommunityPluginVaultBridge.swift:13-369](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L13-L369)), `appearance.json` ([ObsidianAppearance.swift:97-209](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L97-L209)) and theme tokens ([VaultThemeTokens.swift:129-405](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L129-L405)).
- **The host** (GraphiteUI): `CommunityPluginHost`, a `@MainActor @Observable` class of 771 code lines in one block ([CommunityPluginHost.swift:162-1122](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L162-L1122)) plus extensions in five more files (menus, themes, typing, reading blocks, views). It owns the web view, the message transport in both directions, plugin state, editor bridging, notices, menus, views and styles.
- **Views and theme measurement** (GraphiteUI): settings pages, the plugin panel, the notice stack, copies of plugin-drawn blocks in small script-less web views ([CommunityPluginReadingBlocks.swift:738-803](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L738-L803)), and `ThemeTokenResolver`, which measures a theme's computed CSS in an off-screen web view ([ThemeTokenResolver.swift:36-198](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L36-L198)).

**The three biggest problems.**

1. **One aggregate owns the whole plugin runtime.** `CommunityPluginHost` has 63 stored properties (counted by reading lines 166-291) and 12 responsibilities. Its lifecycle is a set of booleans (`isRuntimeRunning`, `isPageLoaded`, `pageLoadFailure`) plus web view identity checks. The "stopping" phase is indistinguishable from "running", which produces BUG-PLUGIN-01. A hand reset of 35 fields in `stopRuntime` ([CommunityPluginHost.swift:515-557](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L515-L557)) misses 13.
2. **The message protocol with the JavaScript runtime is untyped on both sides.** 83 operation names and 16 failure kinds are string literals. Unknown operations from JavaScript fall through `answerHostOperation`'s `default:` into `receiveNotification`'s `default: break` and are answered `[:]`, a success ([CommunityPluginHost.swift:910-912](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L910-L912), [CommunityPluginHost.swift:1050-1051](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1050-L1051)). Failure kinds coming back from JavaScript are dropped ([CommunityPluginHost.swift:844-846](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L844-L846)). The bridge classifies two Swift errors by the end of their message text ([CommunityPluginVaultBridge.swift:360-361](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L360-L361)).
3. **Correctness at the edges of waiting and stopping.** Six defects (section 5) sit where the host waits on the runtime or on the workspace:
   - a start ignored while a stop is in progress;
   - a plugin load with no timeout;
   - a rename reported as done when it was refused;
   - stale Bases formula values;
   - a keychain read failure erasing secrets;
   - saved plugin views erased whenever the runtime stops.

**The three best parts.**

1. **The vault bridge.** Every request is decoded into a private `Decodable` struct ([CommunityPluginVaultBridge.swift:82-109](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L82-L109)). Every write is revision-checked through `VaultStore.save` ([CommunityPluginVaultBridge.swift:224-239](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L224-L239)). Failures are answers rather than crashes ([CommunityPluginVaultBridge.swift:34-42](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L34-L42)). Vault reads and listings return to JavaScript as JSON text, so the main thread never decodes a note ([CommunityPluginHost.swift:860-866](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L860-L866)).
2. **Obsidian file-format fidelity.** `community-plugins.json` is written as `JSON.stringify(list, null, 2)` and merged with changes made elsewhere ([CommunityPluginList.swift:41-77](../../../Sources/GraphiteCore/CommunityPluginList.swift#L41-L77)). `appearance.json` writes only changed owned keys ([ObsidianAppearance.swift:184-193](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L184-L193)). The installer never touches `data.json` ([CommunityPluginInstaller.swift:116-127](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L116-L127)). Version ordering follows semantic versioning, pre-releases included ([CommunityPluginManifest.swift:60-111](../../../Sources/GraphiteCore/CommunityPluginManifest.swift#L60-L111)).
3. **Theme measurement by WebKit against a default layer.** The probe page computes every `var()`, `calc()` and `color-mix()` as Obsidian does ([theme-probe.js:173-196](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L173-L196)). `ThemeProbeReading.tokens` keeps only values that differ from Graphite's defaults ([VaultThemeTokens.swift:281-288](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L281-L288)). Results are cached by a SHA-256 fingerprint of all inputs, and each measurement has a deadline ([ThemeTokenResolver.swift:20-27](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L20-L27), [ThemeTokenResolver.swift:72-99](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L72-L99)).

**Earlier-pass claims.**

| Claim | Source | Holds? | Evidence |
| --- | --- | --- | --- |
| `Docs/SOLID.md` covers the plugin area | SOLID.md, last reviewed 2026-09-30 | No claim exists | Plugin work began 2026-10-10 ([OBJECTIVE.md:88](../../../OBJECTIVE.md#L88)). SOLID.md's general DIP gap, "Workspace constructs … directly", extends here: `WorkspaceModel` constructs `CommunityPluginHost()` and `ThemeTokenResolver()` itself ([WorkspaceModel.swift:194](../../../Sources/GraphiteUI/WorkspaceModel.swift#L194), [WorkspaceModel.swift:135](../../../Sources/GraphiteUI/WorkspaceModel.swift#L135)). |
| "Every file operation they make goes through `CommunityPluginVaultBridge` and `VaultStore`" | [Architecture.md:119](../../../Docs/Architecture.md#L119) | Partly | Writes go through `VaultStore.save`. Stat, listing, folder listing, the byte-order-mark probe and the "replace" revision read use `FileManager`/`FileHandle` directly ([CommunityPluginVaultBridge.swift:120](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L120), [:161](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L161), [:233](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L233), [:244-248](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L244-L248), [:312-316](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L312-L316)). Folder copies run their own coordinator ([:297-299](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L297-L299)). `fileManager.renameFile` goes through `WorkspaceModel.move`, not the bridge ([CommunityPluginHost.swift:918-934](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L918-L934)). The URL scheme handler reads vault files with `Data(contentsOf:)` ([CommunityPluginWebContent.swift:45-48](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L45-L48)). |
| "Every message Graphite waits on has a timeout (2 s menus, 4 typing, 5 taps, 20 drawing)" | [Architecture.md:349](../../../Docs/Architecture.md#L349) | Partly | The four numbers hold ([CommunityPluginMenus.swift:22](../../../Sources/GraphiteUI/CommunityPluginMenus.swift#L22), [CommunityPluginTyping.swift:27](../../../Sources/GraphiteUI/CommunityPluginTyping.swift#L27), [CommunityPluginReadingBlocks.swift:56-58](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L56-L58)). "Every" does not: `plugin.load`, `runtime.start`, `command.run`, `settings.show`, `ribbon.run`, `view.show` and `vault.changes` use `send(_:)` with no timeout ([CommunityPluginHost.swift:575](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L575), [:476](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L476), [:660](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L660), [:684](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L684)). See BUG-PLUGIN-02. |
| Plugins' JavaScript never runs on the main thread | [Architecture.md:349](../../../Docs/Architecture.md#L349), [OBJECTIVE.md:88](../../../OBJECTIVE.md#L88) | Yes for script execution | The page runs in WebKit's content process. Every message is still validated and re-serialized on the main actor ([CommunityPluginHost.swift:857-861](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L857-L861)); see CC-PLUGIN-06. |
| Plugins never write outside the vault | [OBJECTIVE.md:88](../../../OBJECTIVE.md#L88) | Yes for files | The bridge resolves every path through `VaultPath.url(in:)`. Per-device stores outside the vault are deliberate and documented: keychain secrets ([CommunityPluginSecretStore.swift:7-15](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L7-L15)), the per-vault `WKWebsiteDataStore` ([CommunityPluginHost.swift:373](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L373)) and the clipboard ([CommunityPluginHost.swift:904-906](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L904-L906)). |
| Results cached by "the default layer's version (4)" | [Architecture.md:282](../../../Docs/Architecture.md#L282) | No | The version is 5 ([ThemeTokenResolver.swift:38](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L38)). |
| Theme refresh 300 ms; size write 600 ms; styles gathered 100 ms; measurement deadline 15 s | Architecture.md:113, 114, 282 | Yes | [WorkspaceTheme.swift:10](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L10), [WorkspaceAppearance.swift:9](../../../Sources/GraphiteUI/WorkspaceAppearance.swift#L9), [CommunityPluginThemes.swift:53](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L53), [ThemeTokenResolver.swift:70](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L70). |
| Graphite keeps the last 64 copies | Architecture.md:349 | Yes | [CommunityPluginReadingBlocks.swift:213-220](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L213-L220). |
| Consent per vault in `UserDefaults`; web storage per vault; keychain choice per platform | Architecture.md:119 | Yes | [CommunityPluginHost.swift:287-298](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L287-L298), [:373](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L373), [CommunityPluginSecretStore.swift:22-30](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L22-L30). |
| Views restored after a restart | [Coverage.md:313](../../../Docs/Coverage.md#L313) | Only across an app relaunch | Stopping the runtime (vault switch, reload, turning off) erases the saved views; see BUG-PLUGIN-06. |
| `VaultThemeTokensTests` 5 tests; `ThemeTokenResolverTests` 3 tests | [Coverage.md:437-438](../../../Docs/Coverage.md#L437-L438) | No (stale) | 6 and 4 test functions now (grep `func test` in [VaultThemeTokensTests.swift](../../../Tests/GraphiteCoreTests/VaultThemeTokensTests.swift) and [ThemeTokenResolverTests.swift](../../../Tests/GraphiteUITests/ThemeTokenResolverTests.swift)). |
| `ObsidianAppearanceTests` 14 in all; `CommunityPluginHostTests` 11 in all | Coverage.md:449, 486 | Yes | 14 and 11 test functions (grep `func test`). |
| Theme settings style plugin panels only; notes keep Graphite's look | Comments at [ThemeSettings.swift:4-6](../../../Sources/GraphiteUI/ThemeSettings.swift#L4-L6), [CommunityPluginThemes.swift:4-7](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L4-L7), [ObsidianAppearance.swift:129-130](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L129-L130) | No | Notes take the theme ([WorkspaceTheme.swift:23-56](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L23-L56)), and the same view's footer says so ([ThemeSettings.swift:37-39](../../../Sources/GraphiteUI/ThemeSettings.swift#L37-L39)). |

## 2. File inventory

Physical and code lines come from the reconnaissance; responsibilities come from reading each file.

| File | Physical | Code | Responsibility |
| --- | ---: | ---: | --- |
| [GraphiteApple/CommunityPluginSecretStore.swift](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift) | 81 | 59 | Per-vault plugin secrets as one JSON item in the keychain |
| [GraphiteCore/AccentLegibility.swift](../../../Sources/GraphiteCore/AccentLegibility.swift) | 87 | 57 | WCAG luminance and contrast; smallest lighten/darken that reads |
| [GraphiteCore/CommunityPluginEditorChange.swift](../../../Sources/GraphiteCore/CommunityPluginEditorChange.swift) | 125 | 100 | Minimal edit from a plugin's text **and** Markdown→HTML for `MarkdownRenderer.render` (two concepts) |
| [GraphiteCore/CommunityPluginInstaller.swift](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift) | 171 | 130 | Directory entry and search; GitHub release selection, download, write |
| [GraphiteCore/CommunityPluginInventory.swift](../../../Sources/GraphiteCore/CommunityPluginInventory.swift) | 158 | 116 | Compatibility assessment, installed plugin listing, package read |
| [GraphiteCore/CommunityPluginList.swift](../../../Sources/GraphiteCore/CommunityPluginList.swift) | 78 | 57 | `community-plugins.json` model, Obsidian layout, merged update |
| [GraphiteCore/CommunityPluginManifest.swift](../../../Sources/GraphiteCore/CommunityPluginManifest.swift) | 111 | 85 | Manifest parsing, identifier rule, semantic version order |
| [GraphiteCore/CommunityPluginNetworkRequest.swift](../../../Sources/GraphiteCore/CommunityPluginNetworkRequest.swift) | 55 | 46 | A plugin's `requestUrl` performed with `URLSession`, bounded |
| [GraphiteCore/CommunityPluginVaultBridge.swift](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift) | 369 | 297 | `vault.*` operations answered from the vault, failure kinds |
| [GraphiteCore/ObsidianAppearance.swift](../../../Sources/GraphiteCore/ObsidianAppearance.swift) | 209 | 129 | `appearance.json` model, font lists, member-preserving merge |
| [GraphiteCore/ObsidianThemes.swift](../../../Sources/GraphiteCore/ObsidianThemes.swift) | 194 | 147 | Theme directory entry, style file paths, store listing, theme installer |
| [GraphiteCore/VaultThemeTokens.swift](../../../Sources/GraphiteCore/VaultThemeTokens.swift) | 426 | 329 | Computed CSS colors, contrast guard, theme tokens, probe reading, callout types |
| [GraphiteUI/CommunityPluginHost.swift](../../../Sources/GraphiteUI/CommunityPluginHost.swift) | 1122 | 875 | The runtime host and 9 small supporting types |
| [GraphiteUI/CommunityPluginMenus.swift](../../../Sources/GraphiteUI/CommunityPluginMenus.swift) | 146 | 111 | Plugins' items in file and editor menus |
| [GraphiteUI/CommunityPluginPresentation.swift](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift) | 251 | 206 | Web view placement and parking, panel sheet, notice stack, window modifier |
| [GraphiteUI/CommunityPluginReadingBlocks.swift](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift) | 837 | 437 | Shown copies of code blocks, sections and views; the copy page's HTML and JavaScript; the copy web view |
| [GraphiteUI/CommunityPluginSettings.swift](../../../Sources/GraphiteUI/CommunityPluginSettings.swift) | 308 | 276 | Settings page, installed row, options page, directory browser (with installs) |
| [GraphiteUI/CommunityPluginThemes.swift](../../../Sources/GraphiteUI/CommunityPluginThemes.swift) | 109 | 88 | Theme and snippets sent to the page, `appearance.setConfig`, accent as HSL |
| [GraphiteUI/CommunityPluginTyping.swift](../../../Sources/GraphiteUI/CommunityPluginTyping.swift) | 87 | 64 | `editor-change` chain and plugin suggestions |
| [GraphiteUI/CommunityPluginViews.swift](../../../Sources/GraphiteUI/CommunityPluginViews.swift) | 552 | 429 | Plugin views (tab, sidebar, live), paste and drop, Bases views, a `WorkspaceModel` extension for tabs and restore, view picture |
| [GraphiteUI/CommunityPluginWebContent.swift](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift) | 163 | 130 | `graphite-plugins://` scheme handler, message receiver and navigation policy, external link opener |
| [GraphiteUI/GraphiteTheme.swift](../../../Sources/GraphiteUI/GraphiteTheme.swift) | 252 | 184 | Accent presets, chrome metrics, motion, hairline, color helpers, two view modifiers (eight concepts) |
| [GraphiteUI/ThemeSettings.swift](../../../Sources/GraphiteUI/ThemeSettings.swift) | 164 | 145 | Themes and Snippets section, theme chooser and installer UI |
| [GraphiteUI/ThemeTokenResolver.swift](../../../Sources/GraphiteUI/ThemeTokenResolver.swift) | 218 | 155 | Off-screen WebKit theme measurement, deadline, device cache |
| [GraphiteUI/WorkspaceAppearance.swift](../../../Sources/GraphiteUI/WorkspaceAppearance.swift) | 130 | 86 | `WorkspaceModel`: read, apply and debounce-save `appearance.json`, font size |
| [GraphiteUI/WorkspaceTheme.swift](../../../Sources/GraphiteUI/WorkspaceTheme.swift) | 64 | 47 | `WorkspaceModel`: theme refresh pipeline into `NoteThemeStyle` |
| [GraphiteUI/Resources/ThemeResolver/theme-probe.js](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js) | 198 | 183 | Probe elements and computed-style readout per appearance |
| **Total (27 files)** | **6665** | **4968** | |

## 3. Responsibility maps of the major types

### 3.1 `CommunityPluginHost` (main block 771 code lines, plus extensions)

Declared at [CommunityPluginHost.swift:162-163](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L162-L163). Extensions: [CommunityPluginMenus.swift:20-129](../../../Sources/GraphiteUI/CommunityPluginMenus.swift#L20-L129), [CommunityPluginThemes.swift:8-109](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L8-L109), [CommunityPluginTyping.swift:22-87](../../../Sources/GraphiteUI/CommunityPluginTyping.swift#L22-L87), [CommunityPluginReadingBlocks.swift:210-255](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L210-L255) and [CommunityPluginViews.swift:9-190](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L9-L190). Together the extension blocks span 506 physical lines. Stored properties: 63 (counted by reading lines 166-291). Members: 88 functions and computed properties (49 in the main block, 39 in the extensions; counted by reading).

**Stored state and functions by responsibility**

| # | Responsibility | Stored state | Functions |
| --- | --- | --- | --- |
| A | Consent and per-device storage | `isTurnedOnForVault` | `consentKey(for:)`, `setTurnedOnForVault`, `forgetVault` ([:287-310](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L287-L310)) |
| B | Packages: inventory, enablement, load outcomes | `vaultIdentifier`, `inventory`, `enabledList`, `loadStates`, `unsupportedFeatures`, `runtimeProblems` | `vaultDidOpen`, `vaultWillClose`, `reloadInventory`, `load`, `setEnabled`, `restartPlugins`, `uninstall`, `describe`, `pluginName(of:)` |
| C | Runtime lifecycle and web view | `webView`, `parkingView`, `schemeHandler`, `messageReceiver`, `bridge`, `monitor`, `secretStore`, `pageLoadWaiters`, `isPageLoaded`, `pageLoadFailure`, `isRuntimeRunning`, `appearance`, `workspace` | `startIfNeeded`, `waitForPageLoad`, `runtimePageDidLoad`, `runtimePageDidFail`, `runtimeProcessDidEnd`, `startRuntime`, `applicationConfiguration`, `corePluginDescriptions`, `stopRuntime`, `parkWebViewIfDetached`, `appearanceDidChange` |
| D | Transport and dispatch | none of its own (uses C's `webView` and `bridge`) | `send(_:timeout:)`, `send(_:)`, `answer`, `answerHostOperation`, `receiveNotification`, `failure`; helper classes `FirstOutcome` and `SingleResumption` ([:110-138](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L110-L138)) |
| E | Registries of what plugins contributed | `commands`, `ribbonActions`, `pluginsWithSettings`, `codeBlockLanguages`, `codeBlockLanguageOwners`, `hasFileMenuItems`, `hasEditorMenuItems`, `hasEditorSuggestions`, `hasEditorChangeListeners`, `hasPasteListeners`, `hasDropListeners`, `pluginFileExtensions`, `pluginsTakeOverNotes`, `pluginBasesViews`, `postProcessingPluginIdentifiers` | written only by `receiveNotification` ([:936-1053](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L936-L1053)); read by `runsMarkdownPostProcessors`, `pluginName(drawingLanguage:)`, `mayShowInPluginView` |
| F | Editor bridge | `editorSnapshots`, `editorSnapshotOrder`, `typingRequest`, `lastTypingRevision` | `activeDocumentDidChange`, `activeDocumentDescription`, `editorSnapshot`, `applyEditorChange`, `waitForQueuedInsertions`, `editorDidChange`, `suggestionItems`, `closeSuggestions`, `chooseSuggestion`, `offerPaste`, `offerDrop` |
| G | Surfaces: panel, notices, menus, settings | `isPanelPresented`, `panelTitle`, `isPanelShownInline`, `notices`, `pendingMenu`, `requestedSettingsPlugin` | `panelDidClose`, `showSettings`, `showNotice`, `tapNotice`, `scheduleNoticeRemoval`, `showMenu`, `menuItems`, `fileMenu`, `editorMenu`, `pluginMenu`, `choose`, `dismiss` ×2, `showFileActions` ×2, `editorMenuElement`/`editorMenuItems` |
| H | Plugin views and live views | `pluginViews`, `sidebarViewRequest`, `shownSidebarViewIdentifier`, `hasRestoredViews`, `liveViewIdentifier`, `liveViewPictures`, `liveViewChangeTime`, `webViewReleaseCount` | `sidebarViews`, `pluginView(withIdentifier:)`, `revealView`, `show`, `showLive`, `hideLive`, `openFileInPluginView`, `saveOpenFileViews`, `restoreView`, `closeView`, `openBasesView`, `updateBasesView`, `basesMessage`, `pluginValue` |
| I | Reading-view copies | `shownCodeBlocks`, `lastCodeBlockCopies`, `keptCopyOrder` | `keepCopy`, `sectionInformation`, `openNoteText` |
| J | Styles and theme push | `pluginStyleSheets`, `pluginBodyClasses`, `pluginBodyStyle`, `activeThemeName`, `styleUpdateTask` | `vaultStyles`, `appearanceConfiguration`, `vaultStylesDidChange`, `applyAppearanceSetting`, `hueSaturationLightness`, `updatePluginStyleSheets` |
| K | Vault change forwarding | `pendingVaultChanges`, `vaultChangeTask` | `vaultItemDidChange` ([:797-815](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L797-L815)) |
| L | Workspace commands on the plugins' behalf | none | `run(_ command:)`, `run(_ ribbonAction:)`, `openPluginLink`, `renameFileUpdatingLinks`, and the `workspace.*`, `clipboard.*`, `network.request` and `markdown.render` cases of `answerHostOperation` |

**Calls that cross responsibilities (the coupling a split must preserve)**

- **D → E, G, H, I, J, K.** One switch, `receiveNotification`, writes:
  - the registries (E);
  - notices, panel and settings requests (G);
  - views (H), and calls `workspace?.pluginViewsDidChange()` ([:956](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L956));
  - copies (I, [:994-996](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L994-L996));
  - styles (J, [:986-993](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L986-L993));
  - secrets (A/C, [:1046-1049](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1046-L1049)).
- **C → B, J, H, F.** `startIfNeeded`:
  - loads each plugin (B, [:411-414](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L411-L414));
  - sends styles in `runtime.start` (J, [:474](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L474));
  - restores views through the workspace (H, [:418](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L418));
  - announces the active document (F, [:419](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L419)).
- **C → every other group.** `stopRuntime` resets C, E, F, G, H and I ([:515-557](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L515-L557)).
- **F → G.** A refused editor change shows a notice ([:770](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L770)).
- **J ↔ workspace.** `applyAppearanceSetting` writes `appearance.json` through `workspace.updateVaultAppearance` ([CommunityPluginThemes.swift:65-87](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L65-L87)). In the other direction, `WorkspaceTheme` reads J's `pluginStyleSheets`, `pluginBodyClasses` and `pluginBodyStyle` and the static `hueSaturationLightness` ([WorkspaceTheme.swift:35-44](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L35-L44)).
- **Workspace → H.** `WorkspaceModel` writes `host.pluginViews`, `host.liveViewPictures`, `host.hasRestoredViews` and `host.shownSidebarViewIdentifier` ([CommunityPluginViews.swift:234](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L234), [:282](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L282), [:305](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L305), [:309](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L309)). The `didSet` of `shownSidebarViewIdentifier` calls back into the workspace ([CommunityPluginHost.swift:186-188](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L186-L188)).

**Lifecycle and ordering rules it relies on**

1. `vaultDidOpen` must set `workspace` before `reloadInventory`, and `reloadInventory` must finish before `startIfNeeded`, because the enabled set is filtered from `inventory` ([:315-323](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L315-L323), [:355](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L355)).
2. `isRuntimeRunning` is set before the first `await` of a start, so a second start returns early ([:357](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L357)). It is cleared only at the end of `stopRuntime`, after a wait of up to 2 seconds ([:510-514](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L510-L514), [:556](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L556)). BUG-PLUGIN-01 comes from this gap.
3. The start order is fixed ([:401-419](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L401-L419)):
   1. page load;
   2. `runtime.start`;
   3. `plugin.load` for each enabled plugin, in inventory order (sorted by name, [CommunityPluginInventory.swift:147](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L147));
   4. `plugins.layoutReady`;
   5. `restorePluginViews`;
   6. `activeDocumentDidChange`.
4. After every `await` in `startIfNeeded`, the web view's identity must be checked again, because a stop or another vault may have replaced it. There are 4 such checks (`webView === pluginWebView` at [:404](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L404), [:412](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L412), [:415](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L415), [:417](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L417)).
5. `stopRuntime` must reset every field a running runtime can set. It resets 35 fields (counted by reading lines 515-557), cancels `vaultChangeTask` and moves `.loaded`/`.loading` states back to `.notStarted`. It misses 13 (found by comparing the property list with lines 515-557):
   - it never cancels `styleUpdateTask`;
   - it never resets `pluginStyleSheets`, `pluginBodyClasses`, `pluginBodyStyle`, `activeThemeName`, `notices`, `shownCodeBlocks`, `sidebarViewRequest`, `requestedSettingsPlugin`, `secretStore`, `lastTypingRevision`, `webViewReleaseCount` or `isPanelShownInline`.
6. `restorePluginViews` sets `hasRestoredViews` in a `defer` ([CommunityPluginViews.swift:281-284](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L281-L284)). Only after that may `pluginViewsDidChange` overwrite the saved sidebar views ([CommunityPluginViews.swift:239-242](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L239-L242)).
7. An editor snapshot is recorded before it is sent. A returned change is applied only while the note's text equals that snapshot ([:738-752](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L738-L752), [:768](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L768)).
8. Each `editor.update` awaits the previous one's answer, so plugins hear changes in order ([CommunityPluginTyping.swift:41-44](../../../Sources/GraphiteUI/CommunityPluginTyping.swift#L41-L44)).
9. `appearance` must be set by the window's `.onChange(of: colorScheme, initial: true)` ([CommunityPluginPresentation.swift:239](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L239)) before `runtime.start` reads it ([:471](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L471)).

**Verdict and proposed split.** The type is an application-wide aggregate for plugins. Each group already has a clear boundary, and they share only the transport.

| New type | Single responsibility | Members moved from the host |
| --- | --- | --- |
| `CommunityPluginSession` (one per open vault, created at `vaultDidOpen`, released at close) | Owns the parts below for one vault, so stopping is "release the session" rather than a hand reset | lifecycle of C as an enum (CC-PLUGIN-01); the workspace capabilities it needs (ISP-PLUGIN-01) |
| `CommunityPluginRuntimeConnection` | Web view, page load, `send` with timeout and cancellation, `answer` decoding into typed messages | C's `webView`, `schemeHandler`, `messageReceiver`, `pageLoadWaiters`, `isPageLoaded`, `pageLoadFailure`; D's `send` ×2, `answer`, `failure` |
| `CommunityPluginContributions` (value type, replaced whole) | What loaded plugins registered | all 15 fields of E, built by a typed decoder of the `*.changed` notifications |
| `CommunityPluginPackages` | Inventory, enabled list, load outcomes, consent, install and uninstall | B and A |
| `CommunityPluginEditorBridge` | Snapshots, applying plugin edits, typing chain, paste and drop | F |
| `CommunityPluginSurfaces` | Panel, notices, menus, settings requests | G |
| `CommunityPluginViewRegistry` | Views, live view ownership, pictures, restore state | H, plus the writes the `WorkspaceModel` extension makes to H |
| `CommunityPluginCopyCache` | Shown copies and the 64-entry kept-copy cache | I |
| `CommunityPluginPageStyles` | Page styles, body presentation, theme push, `appearance.setConfig` | J (`hueSaturationLightness` moves to Core beside `ThemeColor`) |
| `VaultChangeForwarder` | Debounced vault change paths to the runtime | K |

Group L stays as intent methods on the session (`runCommand`, `runRibbonAction`, `openPluginLink`). `renameFileUpdatingLinks` moves to `WorkspaceModel`, which returns a typed outcome (BUG-PLUGIN-03).

### 3.2 `ThemeModeTokens` (53 stored properties)

Declared at [VaultThemeTokens.swift:129-258](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L129-L258). It is a `Codable` record persisted in the device cache ([ThemeTokenResolver.swift:190-196](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L190-L196)). It has 53 stored properties (counted by reading lines 130-196), one of them a nested `HeadingTokens` with 11 properties ([:208-227](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L208-L227)).

- **Responsibilities:**
  - one appearance's theme values (the stored properties);
  - coverage reporting (`changedGroups`, `changedGroupCount`, `changedPhaseOneGroupCount`, [:230-257](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L230-L257));
  - the probe class map for code tokens (`codeTokenProbeClasses`, [:201-206](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L201-L206)).
- **Coupling:** `changedGroups` is a positional `[Bool]` of 30 entries, and its order is the contract (`prefix(Self.phaseOneGroupCount)`, [:253](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L253)). A group inserted in the middle shifts the Phase 1 count silently.
- **Ordering rule:** any change to the stored properties changes the cached JSON shape. The cache stays valid only because `ThemeTokenResolver.defaultLayerVersion` is part of every fingerprint ([ThemeTokenResolver.swift:22](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L22)); the record itself has no schema version.
- **Verdict:** a flat value record is acceptable, because its fields mirror CSS groups and carry no behaviour. Two changes:
  - nest the fields in group structs that mirror the 30 groups, as `HeadingTokens` already does;
  - replace `changedGroups: [Bool]` with `enum ThemeTokenGroup: CaseIterable` and `func isChanged(_ group:)`.

### 3.3 `CommunityPluginVaultBridge` (297 code lines)

[CommunityPluginVaultBridge.swift:13-369](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L13-L369): 2 stored properties (`store`, `deletionMethod`), 9 operations, encoding helpers and failure mapping.

- **Responsibilities:**
  - operation dispatch ([:47-78](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L47-L78));
  - listing ([:115-180](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L115-L180));
  - read and write, with the byte order mark policy ([:184-254](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L184-L254));
  - remove and copy ([:258-307](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L258-L307));
  - answer encoding ([:312-340](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L312-L340));
  - failure kinds ([:345-368](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L345-L368)).
- **Coupling:** the failure kind of two `VaultStore` errors depends on their message suffix (CC-PLUGIN-05). Folder copy repeats `VaultStore`'s coordination pattern ([VaultStore.swift:324-330](../../../Sources/GraphiteCore/VaultStore.swift#L324-L330)).
- **Verdict:** cohesive; keep it as one type. Move its direct `FileManager` reads (stat, listing, BOM probe, folder copy) into `VaultStore` methods so the bridge is a pure translator, and replace the string-matched failures with typed errors.

## 4. Findings by principle

### S

#### SRP-PLUGIN-01 `CommunityPluginHost` is one aggregate for the whole plugin runtime
- **Severity:** High
- **Evidence:**
  - 63 stored properties ([CommunityPluginHost.swift:166-291](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L166-L291), counted by reading), 88 members over six files and 12 responsibilities (section 3.1).
  - One switch, `receiveNotification`, writes into seven of the responsibility groups ([CommunityPluginHost.swift:936-1053](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L936-L1053)).
  - 20 view and helper types hold the host whole (grep `host: CommunityPluginHost` in `Sources/GraphiteUI`).
- **Why it matters:**
  - Every plugin feature (menus, typing, views, Bases, themes, notices) changes this one type: 21 commits touch the file, the most in the area (reconnaissance).
  - Nothing in it can be tested without a hosted app, a window and a running WebKit page. The 11 tests in [CommunityPluginHostTests.swift](../../../App/Tests/CommunityPluginHostTests.swift) are iOS-hosted integration tests.
  - Missed resets (SRP-PLUGIN-02) and the lifecycle defect (BUG-PLUGIN-01) follow from the shared state.
- **Fix direction:** a per-vault `CommunityPluginSession` composed of the ten parts listed in section 3.1, each owning its own state. Leaving a vault releases the session instead of resetting fields.

#### SRP-PLUGIN-02 Stopping the runtime depends on a hand reset of 35 fields that misses 13
- **Severity:** Medium
- **Evidence:**
  - [CommunityPluginHost.swift:515-557](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L515-L557) assigns 35 fields one by one; the 13 omissions are listed in section 3.1, rule 5.
  - `pluginStyleSheets`, `pluginBodyClasses` and `pluginBodyStyle` ([:239-243](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L239-L243)) survive a vault switch. `WorkspaceTheme` feeds them to the theme resolver whenever `isRuntimeRunning` is true ([WorkspaceTheme.swift:36](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L36), [:43-44](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L43-L44)), and the next start sets that flag before the new page has sent its styles ([CommunityPluginHost.swift:357](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L357)).
  - `styleUpdateTask` is never cancelled on stop ([CommunityPluginThemes.swift:50-59](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L50-L59)).
  - `vaultWillClose` resets 6 more fields itself ([CommunityPluginHost.swift:326-335](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L326-L335)).
- **Why it matters:** every new piece of plugin state must be added in two places (its declaration and the reset), and the compiler checks neither. A forgotten reset carries one vault's plugin state into the next:
  - another vault's styles enter a theme measurement until the new page sends `styles.changed`;
  - notices linger until their timers fire.
- **Fix direction:** group the plugin-contributed state into one value (`CommunityPluginContributions`) with an `empty` value assigned in one statement, and keep per-runtime objects in the session that is released on stop.

#### SRP-PLUGIN-03 Settings and reading views perform network installs and vault reads
- **Severity:** Medium
- **Evidence (6 view functions doing I/O, counted by reading):**
  - views construct installers and run them: [CommunityPluginSettings.swift:87-99](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L87-L99) (`CommunityPluginInstaller(store:).install` from a text field), [:280-290](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L280-L290) and [:292-307](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L292-L307) (directory and install), [ThemeSettings.swift:141-148](../../../Sources/GraphiteUI/ThemeSettings.swift#L141-L148) and [:150-163](../../../Sources/GraphiteUI/ThemeSettings.swift#L150-L163) (theme directory and install);
  - `CommunityPluginSectionView.tickTask` reads a note from the store, splits lines and computes the task location inside a view ([CommunityPluginReadingBlocks.swift:370-389](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L370-L389)).
- **Why it matters:** install outcomes ("Installed version …", "older release", compatibility text) are composed in two views with different wording ([CommunityPluginSettings.swift:93](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L93), [:300-302](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L300-L302)). None of it is testable without SwiftUI, and the install path has no unit test (DIP-PLUGIN-02).
- **Fix direction:** a `CommunityPluginInstallation` model (in the packages part of the session) with `install(repository:)`, `install(entry:)` and a typed `InstallationOutcome`; a `ThemeInstallation` counterpart; `tickTask` becomes a call to the reading-tasks model with the section's line.

#### SRP-PLUGIN-04 A `WorkspaceModel` extension in a plugin file writes host state, and the host calls back into it
- **Severity:** Medium
- **Evidence:**
  - [CommunityPluginViews.swift:192-312](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L192-L312) extends `WorkspaceModel` with tab placement, layout saving and view restore. It writes `host.liveViewPictures` ([:234](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L234)), `host.hasRestoredViews` ([:282](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L282)), `host.pluginViews` ([:305](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L305)) and `host.shownSidebarViewIdentifier` ([:309](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L309)).
  - The host calls `workspace.pluginViewsDidChange()`, `openPluginViewInTab`, `openPluginViewBeside` and `restorePluginViews` ([CommunityPluginHost.swift:187](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L187), [:418](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L418), [:956](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L956), [CommunityPluginViews.swift:22-23](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L22-L23)).
- **Why it matters:** the order of these mutual calls decides what the saved layout contains; BUG-PLUGIN-06 is the outcome. Neither type owns "which plugin view is in which tab".
- **Fix direction:** `CommunityPluginViewRegistry` owns view identities and restore state and publishes changes; the workspace's tab layout observes it; only the registry writes view state.

#### SRP-PLUGIN-05 `GraphiteTheme.swift` holds eight unrelated concepts
- **Severity:** Low
- **Evidence:**
  - accent presets ([GraphiteTheme.swift:4-16](../../../Sources/GraphiteUI/GraphiteTheme.swift#L4-L16));
  - chrome metrics ([:22-39](../../../Sources/GraphiteUI/GraphiteTheme.swift#L22-L39));
  - motion ([:43-62](../../../Sources/GraphiteUI/GraphiteTheme.swift#L43-L62));
  - `Hairline` ([:65-76](../../../Sources/GraphiteUI/GraphiteTheme.swift#L65-L76));
  - `AppearanceVariants` and platform color helpers ([:80-193](../../../Sources/GraphiteUI/GraphiteTheme.swift#L80-L193));
  - the `accent` environment value ([:202-206](../../../Sources/GraphiteUI/GraphiteTheme.swift#L202-L206));
  - `Color.sRGBHex` ([:208-222](../../../Sources/GraphiteUI/GraphiteTheme.swift#L208-L222));
  - two layout modifiers, `sidebarBar` and `formFooterAlignment` ([:224-252](../../../Sources/GraphiteUI/GraphiteTheme.swift#L224-L252)).
- **Why it matters:** the file name names none of these. A design-token cleanup has to read the whole file to find what is a token.
- **Fix direction:** one file per concept: `GraphiteAccent.swift`, `GraphiteChrome.swift`, `GraphiteMotion.swift`, `PlatformColor+Appearance.swift`, `SidebarBar.swift`, `FormFooterAlignment.swift`.

#### SRP-PLUGIN-06 `CommunityPluginEditorChange.swift` holds a text diff and a Markdown renderer
- **Severity:** Low
- **Evidence:** `CommunityPluginEditorChange` ([CommunityPluginEditorChange.swift:8-33](../../../Sources/GraphiteCore/CommunityPluginEditorChange.swift#L8-L33)) and `CommunityPluginMarkdownRendering` ([:40-125](../../../Sources/GraphiteCore/CommunityPluginEditorChange.swift#L40-L125)), which share no code.
- **Why it matters:** the renderer (highlight and callout marking) cannot be found by the file name.
- **Fix direction:** move `CommunityPluginMarkdownRendering` to a file of that name.

### O

#### OCP-PLUGIN-01 The runtime message protocol is 83 untyped operation names in parallel switches; unknown operations succeed
- **Severity:** High
- **Evidence:**
  - **JavaScript→Swift: 44 names** in three Swift switches: the bridge's 9 ([CommunityPluginVaultBridge.swift:49-77](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L49-L77)), `answerHostOperation`'s 9 ([CommunityPluginHost.swift:871-913](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L871-L913)) and `receiveNotification`'s 26 ([:938-1052](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L938-L1052)). The callers are 70 call sites in 9 runtime JavaScript files (grep `hostBridge\.(send|notify)\('([a-zA-Z.]+)'` in `Resources/CommunityPluginRuntime/*.js`).
  - **Swift→JavaScript: 39 names** (counted by reading every `"operation":` literal in the six host files). They are answered by the `messageHandlers` object in [community-plugin-runtime-plugins.js:1244-1538](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1244-L1538) and by handlers merged in from other runtime files.
  - **Unknown operations:** `answerHostOperation`'s `default:` hands the message to `receiveNotification`, whose `default: break` returns, and the caller answers `[:]` ([CommunityPluginHost.swift:910-912](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L910-L912), [:1050-1051](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1050-L1051)). The JavaScript side refuses unknown operations with `unknownOperation` ([community-plugin-runtime-plugins.js:1541-1543](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1541-L1543)), so the two directions disagree.
  - **Shared prefix:** `vault.` is used in both directions. `vault.changes` and `vault.configuration` go Swift→JavaScript ([CommunityPluginHost.swift:810-812](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L810-L812)), while `CommunityPluginVaultBridge.handles` routes every incoming `vault.` name to the bridge ([CommunityPluginVaultBridge.swift:30](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L30)).
- **Why it matters:** a misspelt or renamed operation on either side compiles and passes the Node tests, whose host also answers `{}` by default ([test-vault-host.js:126-128](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L126-L128)). In the app it does nothing. Adding one operation touches 3 to 5 places: a Swift switch, a JavaScript call site, often a stored property and its reset, and the Node test host.
- **Fix direction:** two Swift enums, `CommunityPluginHostOperation` (incoming) and `CommunityPluginRuntimeOperation` (outgoing):
  - `String` raw values, plus an explicit `unknown(String)` decoding case that answers `unknownOperation`;
  - a build step that generates `community-plugin-operations.js` from them, so JavaScript uses constants;
  - each incoming case decodes a `Decodable` payload struct, as the bridge already does.

#### OCP-PLUGIN-02 Each plugin-contributed capability is added in four places
- **Severity:** Medium
- **Evidence:** the paste listener flag, for example, has a declaration ([CommunityPluginHost.swift:209](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L209)), a decode ([:967](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L967)), a reset ([:543](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L543)) and a JavaScript notification ([community-plugin-runtime-plugins.js:1059](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1059)). The same four-place pattern holds for all 15 registry fields of group E.
- **Why it matters:** the reset is the step that gets forgotten (SRP-PLUGIN-02).
- **Fix direction:** `CommunityPluginContributions` as one `Decodable` value per notification kind, replaced whole, with an `empty` value.

#### OCP-PLUGIN-03 The theme probe's vocabulary is declared twice, in JavaScript and in Swift
- **Severity:** Medium
- **Evidence:**
  - Probe keys are written in [theme-probe.js:83-171](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L83-L171) and read by literal in [VaultThemeTokens.swift:281-381](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L281-L381): 68 key forms, 159 keys once expanded per heading level, callout type and token class (counted by reading `readValues`).
  - The 27 callout types are listed in [theme-probe.js:8-10](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L8-L10) and again as the keys of [VaultThemeTokens.swift:410-419](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L410-L419) (both 27, the same names).
  - The 11 code token classes are in [theme-probe.js:12](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L12) and [VaultThemeTokens.swift:201-206](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L201-L206).
- **Why it matters:** a key renamed on one side reads as "the theme leaves it alone" (`changed` returns nil, [VaultThemeTokens.swift:282-285](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L282-L285)), so the theme silently stops applying. Only the macOS resolver tests would notice, and only for the keys they assert.
- **Fix direction:** a Swift `ThemeProbeKey` enum, with the callout and token lists passed to `GraphiteThemeProbe.measure` as arguments, so the JavaScript holds no lists of its own; or generate the lists from Swift.

#### OCP-PLUGIN-04 Core plugin descriptions for the runtime are a hard-coded list
- **Severity:** Low
- **Evidence:** 7 entries with identifiers and options ([CommunityPluginHost.swift:490-504](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L490-L504)).
- **Why it matters:** a new Graphite core feature that plugins look up through `app.internalPlugins` must be added here by hand, apart from the core plugin's own declaration.
- **Fix direction:** a `CorePlugin.obsidianIdentifier` and an options provider declared with each core plugin, iterated here.

### L

#### LSP-PLUGIN-01 The Node tests' vault host differs from the Swift bridge in seven behaviours, one of which hides a bug
- **Severity:** High
- **Evidence:** the bridge's own comment says the two "must keep the same operations, answers and failure kinds" ([CommunityPluginVaultBridge.swift:10-12](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L10-L12)). No shared contract suite exists. Comparing [test-vault-host.js:74-212](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L74-L212) with the Swift code gives these differences:

| # | Operation | Node test host | Production |
| --- | --- | --- | --- |
| 1 | `workspace.renameFile` | Runs `vault.rename`, which throws `exists` for a taken destination ([:107-110](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L107-L110), [:94](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L94)) | Reports success when the destination exists (BUG-PLUGIN-03) |
| 2 | `vault.remove` with `system` | Deletes permanently and reports `systemTrash` ([:210-211](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L210-L211)) | Moves to the system trash ([CommunityPluginVaultBridge.swift:271](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L271)) |
| 3 | `vault.remove` with `vaultSetting` | Always the vault trash ([:203](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L203)) | The vault's setting ([CommunityPluginVaultBridge.swift:274](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L274)) |
| 4 | `vault.write` with no expectation | Defaults to `replace` ([:186](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L186)) | Decoding fails with `invalidData` ([CommunityPluginVaultBridge.swift:98](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L98)) |
| 5 | `vault.stat` | Adds `storedPath` ([:80](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L80)) | No such key ([CommunityPluginVaultBridge.swift:57](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L57)) |
| 6 | `vault.list` / `vault.listFolder` | Follows symbolic links and lists links that leave the vault ([:132-158](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L132-L158)) | Skips links, and links leaving the vault ([CommunityPluginVaultBridge.swift:126](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L126), [:168](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L168)) |
| 7 | `vault.read` over the cap without `maximumBytes` | Reads the file ([:165-166](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L165-L166)) | Fails with `tooLarge` ([CommunityPluginVaultBridge.swift:196-198](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L196-L198)) |

- **Why it matters:** the Node suite (84 runtime tests per [Coverage.md:321](../../../Docs/Coverage.md#L321)) tests the runtime against a host that is safer than production for rename and less safe for trash. A runtime change that relies on rename refusing a taken name passes in Node and fails in the app.
- **Fix direction:** one contract fixture, a JSON list of request→expected-answer cases, run by a Swift test against `CommunityPluginVaultBridge` and by a Node test against the test host. `workspace.renameFile` gets its own cases once production returns a typed outcome.

#### LSP-PLUGIN-02 Seven reads turn a failure into an empty result
- **Severity:** Medium
- **Evidence (counted by reading):**
  1. `CommunityPluginSecretStore.secrets()` returns `[:]` for any keychain status other than success, and for undecodable data ([CommunityPluginSecretStore.swift:40-50](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L40-L50)); `setSecret` writes on top of that result (BUG-PLUGIN-05).
  2. `VaultStore.configurationData(at:)` returns nil for an unreadable file ([VaultStore.swift:254-257](../../../Sources/GraphiteCore/VaultStore.swift#L254-L257)), which `communityPluginList()` reads as "no plugin is on" ([CommunityPluginList.swift:53-55](../../../Sources/GraphiteCore/CommunityPluginList.swift#L53-L55)).
  3. `applicationConfiguration()` returns `[:]` for an unreadable `app.json` ([CommunityPluginHost.swift:480-486](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L480-L486)).
  4. `appearanceConfiguration()` does the same for `appearance.json` ([CommunityPluginThemes.swift:38-44](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L38-L44)).
  5. `installedThemeNames()` and `snippetNames()` return `[]` on a listing failure ([ObsidianThemes.swift:84-100](../../../Sources/GraphiteCore/ObsidianThemes.swift#L84-L100)).
  6. A failed folder listing counts as an empty folder before a non-recursive permanent remove ([CommunityPluginVaultBridge.swift:266](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L266)).
  7. A failed byte-order-mark probe writes without the mark ([CommunityPluginVaultBridge.swift:216](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L216)).
- **Why it matters:**
  - Plugins see Obsidian's defaults instead of the vault's settings and may write them back through `vault.setConfig`.
  - Item 6 lets `rmdir(path, false)` delete a non-empty folder permanently when its listing fails.
  - Item 1 loses secrets.
- **Fix direction:** throwing reads with a distinct `notFound`. Callers that want a default for "absent" ask for it explicitly, and every other failure reaches the caller.

#### LSP-PLUGIN-03 `send` hides the runtime's failure kinds and treats a non-object answer as success
- **Severity:** Medium
- **Evidence:**
  - A JavaScript failure `{kind, message}` becomes `GraphiteError.unavailable(message)` ([CommunityPluginHost.swift:844-846](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L844-L846)).
  - `answer as? [String: Any] ?? [:]` turns `undefined` or any non-object answer into an empty success ([:843](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L843)).
  - Callers then compare `answer["outcome"] as? String == "failed"` ([:661-664](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L661-L664), [CommunityPluginMenus.swift:59](../../../Sources/GraphiteUI/CommunityPluginMenus.swift#L59), [CommunityPluginTyping.swift:82](../../../Sources/GraphiteUI/CommunityPluginTyping.swift#L82)), a second failure channel beside `failure`.
- **Why it matters:** "the runtime does not know this operation" (`unknownOperation`) and "the plugin threw" (`runtime`) reach the person as the same kind of notice, and code cannot react to the kind.
- **Fix direction:** a typed `CommunityPluginRuntimeError` whose cases are the kinds, plus `unknown(String)`, thrown by `send`; one outcome convention for answers.

#### LSP-PLUGIN-04 `CommunityPluginShownCodeBlock` serves blocks, sections and views with different contracts
- **Severity:** Low
- **Evidence:**
  - `draw` registers the block and then returns early for `.view` ([CommunityPluginReadingBlocks.swift:81-96](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L81-L96)).
  - Views use `attachView` instead, which builds a request with a placeholder `note: .root` ([:119-134](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L119-L134)).
  - `.unchanged` happens only for sections ([:306-308](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L306-L308)).
  - `CommunityPluginCodeBlockDisplay` and `CommunityPluginCodeBlockCopy` ([:31-34](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L31-L34)) also serve views.
- **Why it matters:** callers must know which methods are valid for which kind, and the "code block" names mislead readers of the view code ([CommunityPluginViews.swift:339](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L339), [:359](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L359)).
- **Fix direction:** `CommunityPluginShownCopy` with a `Source` enum (`codeBlock`, `section`, `view`) whose cases carry what each needs, and kind-specific start methods.

### I

#### ISP-PLUGIN-01 The host takes the whole workspace, and views take the whole host
- **Severity:** High
- **Evidence:**
  - The host uses 24 members of `WorkspaceModel` through `weak var workspace` ([CommunityPluginHost.swift:258](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L258); counted by reading). They include `store`, `folderAccess`, `currentVaultIdentifier`, `errorMessage`, `vaultSettings`, `recentFiles`, `dailyNoteSettings`, `templateSettings`, `preferences`, `markdownSession`, `selection`, `openMarkdownSession`, `open`, `follow`, `move`, `pendingMove`, `pluginViewsDidChange`, `restorePluginViews`, `vaultAppearance` and `updateVaultAppearance`.
  - In the other direction, 20 types hold the whole host. `CommunityPluginFileActionsButton` uses 3 of its members ([CommunityPluginMenus.swift:132-146](../../../Sources/GraphiteUI/CommunityPluginMenus.swift#L132-L146)) and `CommunityPluginNoticeStack` uses 2 ([CommunityPluginPresentation.swift:162-201](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L162-L201)).
- **Why it matters:** host and workspace form a cycle, so each can be built only with the other; this is why every host test is a hosted app test. Views see the host's 63-property surface.
- **Fix direction:** the host receives narrow capabilities:
  - a vault-files handle;
  - `EditorSessionAccess` (`activeSession`, `openSession(at:)`);
  - `WorkspaceNavigation` (`open`, `follow`, and `move` returning outcomes);
  - an `AppearanceSettings` writer.

  Views receive only the part of the session they show (`CommunityPluginSurfaces`, `CommunityPluginViewRegistry`, …).

#### ISP-PLUGIN-02 21 host properties are writable from outside the host
- **Severity:** Medium
- **Evidence:**
  - The 21 properties without `private(set)` (counted by reading lines 166-291): `pluginViews`, `notices`, `pendingMenu`, `isPanelPresented`, `sidebarViewRequest`, `shownSidebarViewIdentifier`, `hasRestoredViews`, `requestedSettingsPlugin`, `liveViewIdentifier`, `liveViewPictures`, `liveViewChangeTime`, `webViewReleaseCount`, `typingRequest`, `lastTypingRevision`, `styleUpdateTask`, `activeThemeName`, `shownCodeBlocks`, `lastCodeBlockCopies`, `keptCopyOrder`, `parkingView`, `isPanelShownInline`.
  - Writers outside the host include [SettingsView.swift:96](../../../Sources/GraphiteUI/SettingsView.swift#L96), [VaultSidebar.swift:83](../../../Sources/GraphiteUI/VaultSidebar.swift#L83), [CommunityPluginPresentation.swift:109](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L109), [:223](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L223), [CommunityPluginSettings.swift:213-217](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L213-L217), [CommunityPluginReadingBlocks.swift:82](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L82) and [CommunityPluginViews.swift:305](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L305).
- **Why it matters:** `isPanelShownInline` passes an outcome through a shared field. A settings page sets it so that a later `surface.present` is routed there ([CommunityPluginHost.swift:1035-1039](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1035-L1039)). Two pages showing at once, or a page that disappears without `onDisappear`, leave it wrong.
- **Fix direction:** intent methods (`presentOptions(of:)`, `dismissMenu(choosing:)`, `requestSidebarView(_:)`) on the owning part. Extension files that need the state move into the part that owns it, so `private` works.

#### ISP-PLUGIN-03 Messages cross the boundary as `[String: Any]` with silent defaults
- **Severity:** Medium
- **Evidence:**
  - 96 lines in scope contain `[String: Any]` (grep `\[String: Any\]` over `Sources/**/CommunityPlugin*.swift` and `ThemeTokenResolver.swift`): 43 in the host file, 14 in the bridge, 10 in reading blocks, 7 in views, 5 each in menus and themes, 4 in the secret store, 3 in typing, 2 in the resolver, and 1 each in the installer, manifest and network request.
  - Incoming values are read with `as?` and silent defaults. A view without a `placement` becomes a tab ([CommunityPluginHost.swift:953](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L953)), and a notice duration defaults to 4,500 ms ([:1027](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1027)).
- **Why it matters:** a misnamed key is not an error but a default value. In the bridge, which decodes typed structs ([CommunityPluginVaultBridge.swift:82-109](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L82-L109)), the same mistake is caught as `invalidData`.
- **Fix direction:** extend the bridge's pattern to every incoming operation (one `Decodable` payload per `CommunityPluginHostOperation` case) and to every answer the host reads.

### D

#### DIP-PLUGIN-01 The host constructs its I/O collaborators and reads `UserDefaults.standard`
- **Severity:** Medium
- **Evidence:**
  - `VaultMonitor`, `VaultStore`, `CommunityPluginVaultBridge`, `CommunityPluginSecretStore`, `CommunityPluginSchemeHandler`, `WKWebViewConfiguration` and `WKWebsiteDataStore(forIdentifier:)` are built inside `startIfNeeded` ([CommunityPluginHost.swift:360-381](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L360-L381)).
  - Consent is stored in `UserDefaults.standard` at 3 sites ([:295](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L295), [:302](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L302), [:318](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L318)).
  - `forgetVault` is `static` and reaches the keychain and WebKit ([:301-310](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L301-L310)).
  - `WorkspaceModel` constructs the host ([WorkspaceModel.swift:194](../../../Sources/GraphiteUI/WorkspaceModel.swift#L194)).
- **Why it matters:** the hosted tests share the device's real `UserDefaults` and keychain ([CommunityPluginHostTests.swift:88-103](../../../App/Tests/CommunityPluginHostTests.swift#L88-L103), [:152-153](../../../App/Tests/CommunityPluginHostTests.swift#L152-L153)), so they are not hermetic, and consent logic cannot be unit-tested.
- **Fix direction:** the composition root passes a `CommunityPluginDeviceStorage` (consent flags, secrets, website data removal) and a runtime factory into the session. The consent key moves into the typed preferences registry.

#### DIP-PLUGIN-02 Default arguments construct network sessions, and the network paths have no tests
- **Severity:** Medium
- **Evidence:**
  - `session: URLSession = .shared` appears in [CommunityPluginInstaller.swift:48](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L48) and [ObsidianThemes.swift:131](../../../Sources/GraphiteCore/ObsidianThemes.swift#L131), and `perform(using session: URLSession = .shared)` in [CommunityPluginNetworkRequest.swift:27](../../../Sources/GraphiteCore/CommunityPluginNetworkRequest.swift#L27).
  - No test calls `install`, `directory` or `perform`. A grep of `install\(|\.perform\(|CommunityPluginNetworkRequest|ObsidianThemeInstaller` over `Tests/**` finds only `ObsidianThemeInstaller.manifestValue` ([ObsidianAppearanceTests.swift:254](../../../Tests/GraphiteCoreTests/ObsidianAppearanceTests.swift#L254)) and unrelated UI `perform` calls. The installer's tested parts are `newestCompatibleVersion` and `isUsableRepository` ([CommunityPluginTests.swift:206-240](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L206-L240)).
- **Why it matters:** release selection on a 404, the identifier checks, the removal of an old `styles.css` and the response size cap all ship untested.
- **Fix direction:** a small `HTTPDownloading` port (`func data(for: URLRequest) async throws -> (Data, HTTPURLResponse)`), with `URLSession` as the production adapter and a scripted fake in test support. This is a real test need, so the protocol is justified.

#### DIP-PLUGIN-03 Platform statics in logic, and display text in Core
- **Severity:** Low
- **Evidence:**
  - Platform statics: `UIDevice.current` ([CommunityPluginHost.swift:465](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L465)), `UIApplication.shared` and `NSWorkspace.shared` ([CommunityPluginWebContent.swift:155-162](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L155-L162)), `Pasteboard` ([CommunityPluginHost.swift:903-905](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L903-L905)), `ContinuousClock.now` ([CommunityPluginViews.swift:68](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L68), [CommunityPluginHost.swift:931](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L931)).
  - The Caches folder through `FileManager.default` ([ThemeTokenResolver.swift:178-180](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L178-L180)).
  - Display text in Core: `ResolvedFontFamily.displayName` ("System Font", …) ([ObsidianAppearance.swift:17-25](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L17-L25)).
- **Why it matters:** timing rules (the 1.5 s live-view picture rule) and the theme cache cannot be tested with a controlled clock or folder, and Core carries user-visible strings.
- **Fix direction:** an injected clock and cache location, and `displayName` moved to a UI presenter.

### Clean code

#### CC-PLUGIN-01 The runtime lifecycle is a set of booleans and identity checks, not a state enum
- **Severity:** High
- **Evidence:** the phases stopped → loading page → starting → loading plugins → running → stopping are spread over several variables and checks:
  - `isRuntimeRunning` ([CommunityPluginHost.swift:194](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L194));
  - `isPageLoaded` and `pageLoadFailure` ([:270-271](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L270-L271));
  - `pageLoadWaiters` ([:269](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L269));
  - four `webView === pluginWebView` checks ([:404-417](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L404-L417)).

  "Stopping" has no representation: `isRuntimeRunning` stays true for up to 2 seconds while `runtime.stop` is awaited ([:507-514](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L507-L514)). The flag is read 35 times in the plugin files (grep `isRuntimeRunning` over `Sources/GraphiteUI/CommunityPlugin*.swift`: 38 lines, minus the declaration and two assignments).
- **Why it matters:** a start requested during a stop is dropped (BUG-PLUGIN-01). The plugin loads started by `startIfNeeded` cannot be cancelled, only abandoned through the identity checks.
- **Fix direction:** `enum CommunityPluginRuntimePhase { case stopped, starting(Task<Void, Never>), running(CommunityPluginRuntimeConnection), stopping(Task<Void, Never>) }`, changed only by `start()` and `stop()`. A `start()` during `.stopping` awaits that task and then starts. The rule "a flow with more than two states is an enum" applies to `@Observable` UI models as much as to domain code.

#### CC-PLUGIN-02 Four sleep-polling loops wait for other work
- **Severity:** Medium
- **Evidence:**
  - up to 50 × 10 ms for a queued insertion ([CommunityPluginHost.swift:711](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L711));
  - 20 × 10 ms again ([:767](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L767));
  - 200 ms polls while a move question is open ([:928-930](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L928-L930));
  - 100 ms polls for up to 10 s until the destination exists ([:931-932](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L931-L932)).
- **Why it matters:**
  - The rename poll infers the outcome from a file's existence, which is wrong when the destination already existed (BUG-PLUGIN-03).
  - An insertion slower than 500 ms makes a plugin's command start from stale text.
  - A move refused for any other reason holds the plugin for 10 s.
- **Fix direction:** `MarkdownSession` exposes `func insertionsApplied() async`. `WorkspaceModel.move` returns `MoveOutcome` (`.moved`, `.refused(reason)`, `.cancelled`) once the person has answered.

#### CC-PLUGIN-03 Three hand-made "first outcome wins" primitives and 41 unowned tasks
- **Severity:** Medium
- **Evidence:**
  - The three primitives: `FirstOutcome` and `SingleResumption` ([CommunityPluginHost.swift:110-138](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L110-L138)), and the `MeasurementOutcome` with `MeasurementTasks` pair ([ThemeTokenResolver.swift:200-218](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L200-L218)).
  - `send(_:timeout:)` never cancels its sleeping timeout task or the losing send ([CommunityPluginHost.swift:826-832](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L826-L832)), so every keystroke's `editor.update` leaves a 4-second sleeper ([CommunityPluginTyping.swift:45](../../../Sources/GraphiteUI/CommunityPluginTyping.swift#L45)). The resolver does cancel its deadline ([ThemeTokenResolver.swift:80](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L80)), so the two primitives behave differently.
  - 44 lines in `Sources/GraphiteUI/CommunityPlugin*.swift` start a task (grep `Task(\.detached)?(\(priority: [.a-zA-Z]+\))? \{`). Three are stored (`styleUpdateTask`, `vaultChangeTask`, `typingRequest`); the other 41 are owned by nothing, for example notice removal ([CommunityPluginHost.swift:1091-1094](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1091-L1094)) and a deferred counter increment ([:693](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L693)).
  - Ordering is done by deferral: `Task { menu.finish(choosing: nil) }` lets a chosen item answer first ([CommunityPluginPresentation.swift:224-226](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L224-L226)).
- **Why it matters:** each primitive re-solves the same race with its own resume-once rules, and unowned tasks outlive the vault they were started for.
- **Fix direction:** one `withTimeout(_:operation:)` helper built on a task group, cancelling the loser, kept in the allow-listed concurrency primitives file. The session owns its tasks and cancels them when it is released.

#### CC-PLUGIN-04 JavaScript, HTML and CSS live inside Swift strings
- **Severity:** Medium
- **Evidence:**
  - 251 lines of JavaScript ([CommunityPluginReadingBlocks.swift:436-686](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L436-L686)) and 28 lines of HTML and CSS ([:404-431](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L404-L431)) for the copy page.
  - The probe page's HTML ([ThemeTokenResolver.swift:140-145](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L140-L145)).
  - JavaScript snippets at [ThemeTokenResolver.swift:108-110](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L108-L110) and [CommunityPluginReadingBlocks.swift:731](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L731).
  - `GraphiteCodeBlock.show` takes 9 positional arguments, whose order is fixed by the Swift string ([:491](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L491), [:731](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L731)).
  - The probe is already a resource file ([theme-probe.js](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js)), which is the right shape.
- **Why it matters:** the copy page's tap, drag, long-press and morph logic is not linted. It is exercised only by hosted iPad tests (for example [CommunityPluginHostTests.swift:197](../../../App/Tests/CommunityPluginHostTests.swift#L197)), not by the Node suite that tests the rest of the runtime.
- **Fix direction:** move them to `Resources/CommunityPluginCopy/copy-page.html` and `copy-page.js`, pass one options object to `show`, and add jsdom tests beside the runtime's.

#### CC-PLUGIN-05 Failure kinds are classified by the end of an error's message text
- **Severity:** Medium
- **Evidence:** `reason.hasSuffix("already exists.")` maps to `exists` and `reason.hasSuffix("is no longer in the vault.")` maps to `missing` ([CommunityPluginVaultBridge.swift:360-361](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L360-L361)). Both depend on the wording of [VaultStore.swift:312](../../../Sources/GraphiteCore/VaultStore.swift#L312) and [VaultStore.swift:321](../../../Sources/GraphiteCore/VaultStore.swift#L321).
- **Why it matters:** rewording a user-facing message in `VaultStore` changes the error kind plugins receive (`exists` becomes `failed`), and Obsidian's API maps those kinds to different exceptions.
- **Fix direction:** typed `GraphiteError` cases (`alreadyExists(VaultPath)`, `missing(VaultPath)`) thrown by `VaultStore` and matched by case.

#### CC-PLUGIN-06 Every plugin message is validated and re-serialized on the main actor
- **Severity:** Medium
- **Evidence:** `answer` runs on the main actor. For bridge operations it calls `JSONSerialization.isValidJSONObject(message)` and then `JSONSerialization.data(withJSONObject: message)` ([CommunityPluginHost.swift:851-862](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L851-L862)). A `vault.write` may carry 64 MB ([CommunityPluginVaultBridge.swift:22](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L22)), so a large write is walked and copied on the main thread.
- **Why it matters:** [OBJECTIVE.md:88](../../../OBJECTIVE.md#L88) puts editor responsiveness first. A plugin that saves a large drawing (Excalidraw), or a sync plugin writing many files, costs main-thread time on every message. The answer direction already avoids this ([CommunityPluginHost.swift:863-865](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L863-L865)).
- **Fix direction:** the runtime sends bridge requests as one JSON string (`JSON.stringify` in WebKit's process), validated and decoded in a detached task, mirroring the answer path.

#### CC-PLUGIN-07 Installation writes files one at a time with no staging
- **Severity:** Medium
- **Evidence:**
  - Plugin install saves `main.js`, then `manifest.json`, then `styles.css` (or deletes it), each separately ([CommunityPluginInstaller.swift:117-126](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L117-L126)).
  - Theme install saves `manifest.json`, then `theme.css` ([ObsidianThemes.swift:168-169](../../../Sources/GraphiteCore/ObsidianThemes.swift#L168-L169)).
  - Each `write` re-reads the whole existing file only to take its revision ([CommunityPluginInstaller.swift:147-157](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L147-L157)).
- **Why it matters:** if the second write fails (a sync client changed `manifest.json` meanwhile, so the revision check refuses it), the new release's `main.js` sits beside the old manifest. The next load runs new code under the old version number and `minAppVersion`.
- **Fix direction:** download everything first (as now). Then either write into a staging folder inside `.obsidian/plugins/` and replace the plugin's files in one coordinated operation, or write the manifest last so that a partial update stays on the old version.

#### CC-PLUGIN-08 Duplicated logic across the area
- **Severity:** Low
- **Evidence (counted by reading):**
  - `download` and `write` exist twice ([CommunityPluginInstaller.swift:147-170](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L147-L170), [ObsidianThemes.swift:176-193](../../../Sources/GraphiteCore/ObsidianThemes.swift#L176-L193)).
  - Directory search ranking exists twice ([CommunityPluginInstaller.swift:21-33](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L21-L33), [ObsidianThemes.swift:32-43](../../../Sources/GraphiteCore/ObsidianThemes.swift#L32-L43)).
  - Hue from RGB exists twice ([VaultThemeTokens.swift:66-77](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L66-L77), [CommunityPluginThemes.swift:95-106](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L95-L106)).
  - Bisection toward a target contrast exists twice ([AccentLegibility.swift:73-86](../../../Sources/GraphiteCore/AccentLegibility.swift#L73-L86), [VaultThemeTokens.swift:105-116](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L105-L116)).
  - "Read a JSON settings file as `[String: Any]`" exists twice ([CommunityPluginHost.swift:480-486](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L480-L486), [CommunityPluginThemes.swift:38-44](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L38-L44)).
  - The accent as `--accent-h/-s/-l` is built in two shapes ([CommunityPluginThemes.swift:26-28](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L26-L28), [WorkspaceTheme.swift:38-40](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L38-L40)).
- **Why it matters:** the pairs drift. The plugin installer treats a 404 for a required file as an error, while the theme installer treats every 404 as "missing" ([ObsidianThemes.swift:187](../../../Sources/GraphiteCore/ObsidianThemes.swift#L187)).
- **Fix direction:**
  - `ObsidianReleaseDownloader`, shared by both installers;
  - `ObsidianDirectorySearch.rank`;
  - `ThemeColor.hueSaturationLightness`;
  - one `AccentLegibility.smallestMix(toward:reads:)`, also used by the contrast guard;
  - `VaultStore.jsonObject(at:)`.

#### CC-PLUGIN-09 Literal durations, caps and sizes in host logic
- **Severity:** Low
- **Evidence:**
  - In `CommunityPluginHost.swift`, 20 literals (counted by reading):
    - `prefix(50)` ×2 ([:473](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L473), [:719](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L719));
    - `1_048_576` ([:483](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L483));
    - `.seconds(2)` ([:513](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L513));
    - `0..<50` and `10 ms` ([:711](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L711));
    - `> 8` ([:743](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L743));
    - `0..<20` and `10 ms` ([:767](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L767));
    - `300 ms` ([:805](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L805));
    - `200 ms`, `10 s` and `100 ms` ([:929-932](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L929-L932));
    - `> 5` ([:1017](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1017));
    - `prefix(3)`, `> 4` and `4500` ([:1024-1027](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1024-L1027));
    - `> 4` and `6000` ([:1067-1068](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1067-L1068));
    - `.seconds(10)` ([:1076](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1076)).
  - The extensions add `.seconds(5)` ×9, `.seconds(3)`, `.seconds(4)`, `.milliseconds(1500)` ×2, `.seconds(10)` ×3 and `.seconds(1.5)`.
  - The named constants `menuTimeout`, `typingTimeout`, `drawingTimeout`, `tapTimeout` and `maximumKeptCopies` show the intended style.
- **Why it matters:** the documented timeout table (Architecture.md:349) cannot be checked against one declaration, and the same 5-second answer timeout is written 9 times in the extensions plus once in the host.
- **Fix direction:** `CommunityPluginTimeouts` and `CommunityPluginLimits` namespaces with units in the names (`noticeDisplayMilliseconds`, `maximumRecentFilesSent`).

#### CC-PLUGIN-10 Stale and history-narrating comments
- **Severity:** Low
- **Evidence:**
  - **Stale:** [ThemeSettings.swift:4-6](../../../Sources/GraphiteUI/ThemeSettings.swift#L4-L6) ("Graphite's own notes keep their look"), [CommunityPluginThemes.swift:7](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L7), [ObsidianAppearance.swift:95-96](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L95-L96) ("keeps the theme and snippets for later") and [:129-130](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L129-L130) all contradict [WorkspaceTheme.swift:4-6](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L4-L6).
  - **History:** [ThemeTokenResolver.swift:74-76](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L74-L76) ("the deadline held the resolver for its whole 15 seconds …"); a dated measurement at [CommunityPluginPresentation.swift:31](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L31) ("2026-10-10"); [GraphiteTheme.swift:229-230](../../../Sources/GraphiteUI/GraphiteTheme.swift#L229-L230) ("drew a white box").
  - **Project-phase labels:** [VaultThemeTokens.swift:169](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L169), [:239](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L239), [CommunityPluginThemes.swift:4](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L4).
- **Why it matters:** a reader of `ThemeSettings` believes notes are unthemed, the opposite of the behaviour.
- **Fix direction:** rewrite them as present-tense rules, and move incident history to commit messages.

#### CC-PLUGIN-11 Six functions over 40 code lines
- **Severity:** Low
- **Evidence:** sizes are from the reconnaissance; positions were confirmed by reading.
  - `receiveNotification` 118 ([CommunityPluginHost.swift:936](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L936));
  - `ThemeProbeReading.tokens` 96 ([VaultThemeTokens.swift:281](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L281));
  - `startIfNeeded` 59 ([CommunityPluginHost.swift:352](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L352));
  - `stopRuntime` 51 ([:506](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L506));
  - `CommunityPluginInstaller.install` 43 ([CommunityPluginInstaller.swift:84](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L84));
  - `answerHostOperation` 41 ([CommunityPluginHost.swift:870](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L870)).
- **Why it matters:** `receiveNotification` mixes 26 unrelated decodings. `tokens` is long but linear, one token per line, so splitting it by size alone gains nothing.
- **Fix direction:**
  - `receiveNotification` disappears into typed payload decoders (OCP-PLUGIN-01).
  - `startIfNeeded` and `stopRuntime` shrink with the session (SRP-PLUGIN-01).
  - `tokens` splits by token group, matching the nested structs of 3.2.

#### CC-PLUGIN-12 Names that break the naming rule or describe the wrong role
- **Severity:** Low
- **Evidence:**
  - Abbreviations: `repo` ([CommunityPluginInstaller.swift:11](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L11), [ObsidianThemes.swift:10](../../../Sources/GraphiteCore/ObsidianThemes.swift#L10)), which can keep its JSON key through `CodingKeys`; `rawBase` ([CommunityPluginInstaller.swift:86](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L86)); `linktext` ([CommunityPluginHost.swift:894](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L894)).
  - A query that writes state: `activeDocumentDescription(includingEditor:)` records an editor snapshot each time it is called ([CommunityPluginHost.swift:728-752](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L728-L752)).
  - A stringly-typed flag: `appearance` holds the string `"light"` or `"dark"` ([:279](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L279)).
  - Wrong role: "code block" types also name copies of views and sections (LSP-PLUGIN-04).
- **Why it matters:** a caller that builds a description only to log it evicts a real snapshot from the 8-entry window ([:743](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L743)).
- **Fix direction:**
  - rename to `repository`, `rawContentBaseAddress` and `linkText`;
  - name the snapshot-recording call as a command, `makeActiveDocumentMessage()`;
  - type the appearance as `enum RuntimeAppearance: String { case light, dark }`.

#### CC-PLUGIN-13 A plugin's network response is read one byte at a time
- **Severity:** Low
- **Evidence:** `for try await byte in bytes { body.append(byte) … }` runs over up to 64 MB ([CommunityPluginNetworkRequest.swift:44-48](../../../Sources/GraphiteCore/CommunityPluginNetworkRequest.swift#L44-L48)).
- **Why it matters:** the loop iterates once per byte with a size check each time. That is slow for the large downloads sync and AI plugins make, although it runs off the main actor because `perform` is a nonisolated async method.
- **Fix direction:** `URLSession.data(for:)` with a delegate that cancels past the cap, or chunked reads.

#### CC-PLUGIN-14 The theme token cache grows without bound
- **Severity:** Low
- **Evidence:** a new `<fingerprint>.json` is written for every distinct set of inputs ([ThemeTokenResolver.swift:190-196](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L190-L196)). The fingerprint includes the accent and the plugin page styles ([:20-27](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L20-L27)), so every accent or Style Settings change adds a file, and nothing deletes old ones.
- **Why it matters:** RULES.md asks for cache budgets ([RULES.md:60](../../../RULES.md#L60)). The folder is in Caches, which the system may purge, so the cost is disk space only.
- **Fix direction:** keep the newest N fingerprints, pruning at write.

## 5. Defects and latent bugs

#### BUG-PLUGIN-01 Turning community plugins off and on again quickly leaves them off while the switch shows on
- **Trigger:** in Settings › Community Plugins, the person turns "Turn On Community Plugins" off, then on again before the runtime has finished stopping (up to 2 seconds, more while plugins unload).
- **Path:**
  1. The toggle calls `setTurnedOnForVault(false)` ([CommunityPluginSettings.swift:21](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L21)), which stores false and awaits `stopRuntime()` ([CommunityPluginHost.swift:293-297](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L293-L297)).
  2. `stopRuntime` passes its guard and suspends while `runtime.stop` runs, with `isRuntimeRunning` still true ([:507-514](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L507-L514)).
  3. The second toggle calls `setTurnedOnForVault(true)`, which sets `isTurnedOnForVault = true` and calls `startIfNeeded` ([:296-297](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L296-L297)).
  4. `startIfNeeded`'s guard requires `!isRuntimeRunning`, so it returns ([:353](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L353)).
  5. The stop resumes and sets `isRuntimeRunning = false` ([:556](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L556)). Nothing starts again.
- **Effect:** the switch reads on and consent is stored as on, but no plugin runs: no commands, no plugin blocks in notes, and "Starts when community plugins run." under each enabled plugin ([CommunityPluginSettings.swift:154](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L154)). This lasts until the vault is reopened or "Reload Plugins" is pressed. `setEnabled` ([CommunityPluginHost.swift:610](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L610)) and `openPluginLink` ([:1074](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1074)) drop their start the same way when called during a stop.
- **Platforms / reach:** iPad, iPhone and Mac; normal path.
- **Confidence:** Traced.

#### BUG-PLUGIN-02 A plugin whose `onload` never finishes stops every later plugin from loading, and plugin views are never restored
- **Trigger:** an enabled plugin's `onload` returns a promise that never settles (it awaits a network call that hangs, or a condition that never comes). In Obsidian, such a plugin harms no other plugin.
- **Path:**
  1. `startIfNeeded` loads the enabled plugins one after another, awaiting each ([CommunityPluginHost.swift:411-414](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L411-L414)).
  2. `load` awaits `send([... "plugin.load" ...])`, the overload without a timeout ([:575-581](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L575-L581), [:840-848](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L840-L848)).
  3. In the page, `loadPlugin` awaits `plugin.load()` ([community-plugin-runtime-plugins.js:624](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L624)), which awaits `this.onload()` with no timeout ([:382-386](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L382-L386)).
  4. The reply never comes, so `plugins.layoutReady`, `restorePluginViews` and `activeDocumentDidChange` are never reached ([CommunityPluginHost.swift:416-419](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L416-L419)).
- **Effect:**
  - The hanging plugin shows "Starting…" for good ([CommunityPluginSettings.swift:155](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L155)).
  - Plugins after it in name order never load and show "Starts when community plugins run.".
  - `onLayoutReady` callbacks of plugins already loaded never run.
  - Tabs and sidebar views saved from the last session stay empty.
  - "Reload Plugins" repeats the same hang.
- **Platforms / reach:** iPad, iPhone and Mac; normal path.
- **Confidence:** Traced.

#### BUG-PLUGIN-03 A plugin's `fileManager.renameFile` onto an existing name is reported as done, although nothing moved
- **Trigger:** a plugin (a note-naming plugin, Templater's rename) calls `app.fileManager.renameFile(file, newPath)` where `newPath` names another existing file.
- **Path:**
  1. The runtime sends `workspace.renameFile` ([community-plugin-runtime-vault.js:662-669](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L662-L669)).
  2. The host calls `workspace.move(source, to: destination)` ([CommunityPluginHost.swift:925](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L925)).
  3. `move` finds the destination taken, sets `errorMessage` and returns without moving ([WorkspaceFileManagement.swift:92-95](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L92-L95)).
  4. No move is pending, so the wait loop ends at once ([CommunityPluginHost.swift:928-930](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L928-L930)).
  5. `hasMoved()` only checks that a file exists at the destination ([:922-924](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L922-L924)). One does, so the host answers `["stat": NSNull()]`, a success ([:933](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L933)).
  6. The runtime moves its revision record and reconciles its file tree as if the source had moved ([community-plugin-runtime-vault.js:667-668](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L667-L668)).
- **Effect:**
  - The plugin continues as if the rename had happened, while the person sees Graphite's "already exists" alert.
  - The plugin's `TFile` now points at the other, pre-existing note, and its next revision-checked write there is refused as a conflict.
  - The source note disappears from the plugin's file tree until a vault change reloads it.
  - A rename asked for before the first index scan finishes is also refused ([WorkspaceFileManagement.swift:98-101](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L98-L101)); the plugin then waits 10 s and fails with `cancelled` ([CommunityPluginHost.swift:931-933](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L931-L933)).
  - The Node test host refuses the taken-name case ([test-vault-host.js:94](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L94)), so the Node suite cannot catch this bug.
- **Platforms / reach:** iPad, iPhone and Mac; normal path.
- **Confidence:** Traced.

#### BUG-PLUGIN-04 A plugin's Bases view keeps old formula values when results change without changing rows
- **Trigger:** a base shown through a plugin's Bases view type (TaskNotes' Kanban, for example) has a formula column, and a note edit changes a formula's value without changing which notes match or how they group.
- **Path:**
  1. `CommunityPluginBasesViewContent` sends an update only when `resultSignature` changes ([CommunityPluginViews.swift:523-525](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L523-L525)).
  2. The signature holds only the group keys' text and the row paths ([:505](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L505)).
  3. Formula values exist only in the message that `basesMessage` builds ([:142-156](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L142-L156)).
  4. The runtime's `BasesEntry` answers formula properties from the values it last received ([community-plugin-runtime-bases.js:195-200](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L195-L200), [:295-296](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L295-L296)). The plugin re-reads note properties from metadata, but not formulas.
- **Effect:** formula cells in the plugin's view (a computed due-in-days, a sum) show the previous values until a row is added, removed or regrouped. A change to the view's columns (`properties`) with the same rows is not sent either.
- **Platforms / reach:** iPad, iPhone and Mac; any base with a formula shown through a plugin's view type.
- **Confidence:** Traced.

#### BUG-PLUGIN-05 A failed keychain read makes the next plugin secret save erase the vault's other secrets
- **Trigger:** a plugin calls `app.secretStorage.setSecret` while `SecItemCopyMatching` answers anything other than success, or while the stored item's data does not decode as `[String: String]`.
- **Path:**
  1. The runtime notifies `secrets.set` ([community-plugin-runtime-foundation.js:691](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L691)), and the host calls `setSecret` ([CommunityPluginHost.swift:1046-1049](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1046-L1049)).
  2. `setSecret` starts from `secrets()` ([CommunityPluginSecretStore.swift:53](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L53)), which returns `[:]` for every non-success status and for undecodable data ([:47-49](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L47-L49)).
  3. `SecItemUpdate` replaces the stored item with a dictionary holding only the new secret ([:58](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L58)).
- **Effect:** every other plugin's API keys and tokens for that vault are lost. They never sync, so no other device can restore them.
- **Platforms / reach:** iPad, iPhone and Mac. Reading did not settle which read statuses occur while the app is in the foreground. The item is `AfterFirstUnlockThisDeviceOnly` ([:57](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L57)); on the Mac's login keychain, a refused access prompt is a candidate. Undecodable data covers any item written in another format.
- **Confidence:** Partly traced. The code path is certain; how often non-success read statuses occur on a device was not established.

#### BUG-PLUGIN-06 Leaving a vault, reloading plugins or turning them off erases the vault's saved plugin views
- **Trigger:** with a plugin view open in a tab or the sidebar (a calendar, a Kanban), the person switches to another vault, presses "Reload Plugins", or turns community plugins off.
- **Path:**
  1. `openVault` calls `communityPlugins.vaultWillClose()` while the old layout is still current ([WorkspaceModel.swift:299](../../../Sources/GraphiteUI/WorkspaceModel.swift#L299)); `layoutVaultIdentifier` is cleared only later ([:311](../../../Sources/GraphiteUI/WorkspaceModel.swift#L311)). `restartPlugins` and `setTurnedOnForVault(false)` call `stopRuntime` directly ([CommunityPluginHost.swift:620-628](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L620-L628), [:297](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L297)).
  2. `stopRuntime` sends `runtime.stop` and waits for it, with the message handler still installed ([:510-515](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L510-L515)).
  3. In the page, `runtime.stop` unloads every plugin ([community-plugin-runtime-plugins.js:1267-1275](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1267-L1275)). Unloading runs the cleanup `registerView` registered, `detachLeavesOfType` ([:457-460](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L457-L460)). Each `detach` posts `views.changed` at once ([community-plugin-runtime-workspace.js:678-687](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L678-L687), [community-plugin-runtime-foundation.js:46-48](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L46-L48)).
  4. The host, idle on the main actor, applies the shorter list and calls `workspace.pluginViewsDidChange()` ([CommunityPluginHost.swift:949-956](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L949-L956)).
  5. That function clears `pluginViewIdentifier` and `restorablePluginView` for every tab whose view is gone. With `hasRestoredViews` still true, it also replaces the restorable sidebar views with the now-empty list. It then saves the tab layout ([CommunityPluginViews.swift:227-244](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L227-L244)).
  6. `saveTabLayout` writes under the vault being left ([WorkspaceTabs.swift:419-421](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L419-L421)).
- **Effect:** when the person returns to the vault, or after the reload, the tabs that showed plugin views open empty and the sidebar's plugin panels are gone. "Views restored after a restart" ([Coverage.md:313](../../../Docs/Coverage.md#L313)) holds only when the app quits without stopping the runtime. The hosted vault-switch test checks commands and load states, not the layout ([CommunityPluginHostTests.swift:183-195](../../../App/Tests/CommunityPluginHostTests.swift#L183-L195)).
- **Platforms / reach:** iPad, iPhone and Mac; normal path for any plugin that registers a view.
- **Confidence:** Traced. Every Swift and runtime step was read. The `views.changed` messages arrive during the stop wait because the handler stays installed and the main actor is free while `stopRuntime` is suspended.

## 6. What to keep

| # | Design | Evidence | Why it is sound |
| --- | --- | --- | --- |
| 1 | Bridge requests are decoded into private `Decodable` structs; failures go back as `{failure: {kind, message}}` answers | [CommunityPluginVaultBridge.swift:34-44](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L34-L44), [:82-109](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L82-L109) | A malformed message is `invalidData`, never a crash or a default, and the plugin's promise is rejected with a kind Obsidian's API can map. This is the model OCP-PLUGIN-01 and ISP-PLUGIN-03 extend to the host. |
| 2 | Every plugin write is revision-checked (`absent`; `revision`; `replace` reads the current revision); the coordinated write checks again | [CommunityPluginVaultBridge.swift:224-239](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L224-L239); test [CommunityPluginTests.swift:151-164](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L151-L164) | Plugins never silently overwrite an external edit ([OBJECTIVE.md:70](../../../OBJECTIVE.md#L70)). |
| 3 | Plugins' writes go through a second `VaultStore` whose presenter is the runtime's own monitor | [CommunityPluginHost.swift:358-364](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L358-L364) | Graphite's main presenter sees plugin writes as external changes and updates open notes and the index, while the runtime does not hear its own writes back. |
| 4 | Bridge answers go back to WebKit as JSON text | [CommunityPluginHost.swift:860-866](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L860-L866), [community-plugin-runtime-host-connection.js:11-13](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-host-connection.js#L11-L13) | Note text and vault listings are parsed in WebKit's process, not on the main thread. |
| 5 | Listing runs detached, skips hidden items and symbolic links, caps at 250,000 entries and reports `isTruncated`; background reads skip cloud placeholders | [CommunityPluginVaultBridge.swift:115-139](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L115-L139), [:189-191](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L189-L191), [:336-340](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L336-L340) | Work stays bounded at 100,000-file scale, and a plugin's metadata scan does not download the whole iCloud vault ([OBJECTIVE.md:78](../../../OBJECTIVE.md#L78)). |
| 6 | Text reads drop a leading byte order mark; text writes keep an existing one | [CommunityPluginVaultBridge.swift:214-217](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L214-L217), [:252-254](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L252-L254); test [CommunityPluginTests.swift:141-149](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L141-L149) | Matches `TextDecoder` and preserves the file's encoding bytes ([RULES.md:54](../../../RULES.md#L54)). |
| 7 | A plugin's edit to the open note becomes one minimal, surrogate-safe edit through the note's session, applied only while the note still has the text the plugin saw | [CommunityPluginEditorChange.swift:12-32](../../../Sources/GraphiteCore/CommunityPluginEditorChange.swift#L12-L32), [CommunityPluginHost.swift:757-793](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L757-L793); tests [CommunityPluginTests.swift:189-205](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L189-L205) | Undo, folds and scroll position survive. A stale plugin edit is refused, and the plugin gets the current snapshot to retry. |
| 8 | `community-plugins.json` is merged with the file as it is now, written in Obsidian's layout, left untouched when unchanged, created only once a plugin is on, and never overwritten when it is not a list | [CommunityPluginList.swift:18-27](../../../Sources/GraphiteCore/CommunityPluginList.swift#L18-L27), [:41-77](../../../Sources/GraphiteCore/CommunityPluginList.swift#L41-L77); tests [CommunityPluginTests.swift:65-89](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L65-L89) | Obsidian and Graphite share the file without fighting over it. |
| 9 | `appearance.json` writes only owned keys whose value changed against a baseline, keeping unknown keys' bytes | [ObsidianAppearance.swift:184-208](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L184-L208); tests [ObsidianAppearanceTests.swift:97-155](../../../Tests/GraphiteCoreTests/ObsidianAppearanceTests.swift#L97-L155) | A key changed in Obsidian in the meantime keeps its value. |
| 10 | The manifest keeps its exact bytes; an identifier is one path component; versions order semantically, pre-releases first | [CommunityPluginManifest.swift:20-54](../../../Sources/GraphiteCore/CommunityPluginManifest.swift#L20-L54), [:60-111](../../../Sources/GraphiteCore/CommunityPluginManifest.swift#L60-L111); tests [CommunityPluginTests.swift:39-64](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L39-L64), [:214-233](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L214-L233) | The runtime receives every key the author wrote, and an update never installs a beta over a stable release. |
| 11 | The installer checks that the directory's identifier, the current manifest and the release manifest agree; validates the repository and version text; caps every download; never touches `data.json` | [CommunityPluginInstaller.swift:84-128](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L84-L128) | A repository cannot install into another plugin's folder, and a plugin's settings survive updates. |
| 12 | Unreadable plugin folders are listed with their reason rather than dropped | [CommunityPluginInventory.swift:134-146](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L134-L146), [CommunityPluginSettings.swift:76-81](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L76-L81) | The person sees why a plugin is missing. |
| 13 | Consent is per vault and per device, and only enabled plugins run; forgetting a vault removes its consent, secrets and web storage | [CommunityPluginHost.swift:287-310](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L287-L310), [:352-356](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L352-L356) | Matches Obsidian's restricted mode, and nothing is left behind for a forgotten vault. |
| 14 | The scheme handler serves only the bundled runtime folder and vault files resolved through `VaultPath`: read-only, size-capped, and never answering a stopped task | [CommunityPluginWebContent.swift:36-106](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L36-L106) | `getResourcePath` works without opening the file system to the page. |
| 15 | The navigation policy refuses anything that would replace the runtime page; only http, https and mailto links leave the app | [CommunityPluginWebContent.swift:138-152](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L138-L152) | One stray link cannot end every plugin. |
| 16 | The message receiver is a separate object that holds the host weakly | [CommunityPluginWebContent.swift:109-119](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L109-L119) | WebKit retains its message handlers strongly, yet the host can still go away with its vault. |
| 17 | Copies of plugin output run no page script (`allowsContentJavaScript = false`) and use a non-persistent store; Graphite's script runs in its own content world; the morph keeps a field that is being typed in | [CommunityPluginReadingBlocks.swift:755-768](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L755-L768), [:455-483](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L455-L483) | Plugin HTML shown in notes cannot run code, and typing in a copy loses no keys. |
| 18 | The hidden web view is parked inside the window | [CommunityPluginPresentation.swift:29-42](../../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L29-L42); test [CommunityPluginHostTests.swift:169-181](../../../App/Tests/CommunityPluginHostTests.swift#L169-L181) | Plugins' timers keep their full rate without a visible panel. |
| 19 | Typing events are ordered (each waits for the previous answer) and capped at 512 Ki UTF-16 units; only the latest revision's suggestions are shown | [CommunityPluginTyping.swift:31-70](../../../Sources/GraphiteUI/CommunityPluginTyping.swift#L31-L70) | Plugins that track the cursor see changes in order, and stale suggestions never appear. |
| 20 | Theme measurement: WebKit measures the theme against Graphite's default layer and only differing values become tokens; results are cached by a SHA-256 of all inputs plus the layer version; one measurement runs at a time and identical requests share it; a 15 s deadline cancels the loser; a generation counter stops a late measurement from releasing the next one's web view | [ThemeTokenResolver.swift:20-27](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L20-L27), [:47-121](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L47-L121); [VaultThemeTokens.swift:281-288](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L281-L288); tests [ThemeTokenResolverTests.swift](../../../Tests/GraphiteUITests/ThemeTokenResolverTests.swift), [VaultThemeTokensTests.swift](../../../Tests/GraphiteCoreTests/VaultThemeTokensTests.swift) | Exact CSS semantics without a CSS engine of Graphite's own, at a bounded cost per change. |
| 21 | `AccentLegibility` and `ThemeContrastGuard` are pure functions with WCAG constants and tests | [AccentLegibility.swift:7-86](../../../Sources/GraphiteCore/AccentLegibility.swift#L7-L86), [VaultThemeTokens.swift:83-124](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L83-L124); tests [AccentLegibilityTests.swift](../../../Tests/GraphiteCoreTests/AccentLegibilityTests.swift) | A theme can never make note text unreadable. This is the "decide" half that must stay pure. |
| 22 | Secrets stay out of the vault, one item per vault, capped at 1 MB, in the data protection keychain when the process may use it | [CommunityPluginSecretStore.swift:7-63](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L7-L63) | API keys never sync through the vault, as in Obsidian. |
| 23 | Plugin network requests run natively, only for http and https, bounded to 64 MB and 60 s | [CommunityPluginNetworkRequest.swift:13-54](../../../Sources/GraphiteCore/CommunityPluginNetworkRequest.swift#L13-L54) | Obsidian-mobile parity without CORS limits, with bounds. |
| 24 | Plugin writes to `appearance.json` go through a whitelist of seven keys with validated values | [CommunityPluginThemes.swift:65-87](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L65-L87) | A plugin can write neither arbitrary keys nor a theme name that is a path. |
| 25 | Logging marks plugin details private in release builds | [CommunityPluginHost.swift:154-160](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L154-L160) | Plugin messages can name notes. |
| 26 | A terminated content process restarts the runtime | [CommunityPluginHost.swift:442-450](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L442-L450) | Memory pressure on iPad does not leave plugins dead. |

## 7. Blueprint for this area

### Target shape

**GraphiteCore (pure values and policies, no platform types beyond Foundation)**

| Type | Single responsibility |
| --- | --- |
| `CommunityPluginManifest`, `ObsidianVersionNumber`, `CommunityPluginList`, `CommunityPluginCompatibility`, `CommunityPluginInventory` | Unchanged; they are already single-purpose. |
| `CommunityPluginHostOperation` / `CommunityPluginRuntimeOperation` | The two operation vocabularies as enums with raw values and an `unknown(String)` case; the source of the generated JavaScript constants. |
| `CommunityPluginMessages` (one `Decodable` payload struct per incoming operation; `Encodable` payloads for outgoing ones) | Typed message bodies at the WebKit boundary. |
| `CommunityPluginFailureKind` | The 16 failure kinds as an enum, shared by the bridge, the host and the runtime constants. |
| `CommunityPluginVaultBridge` | Unchanged role; it maps typed `VaultStore` errors and calls `VaultStore` for stat and listing. |
| `ObsidianReleaseDownloader` + `HTTPDownloading` port | Release selection and capped downloads for plugins and themes (the port exists for tests). |
| `CommunityPluginInstaller`, `ObsidianThemeInstaller` | Plan an installation (which files, which version) and write it staged. |
| `ObsidianDirectorySearch` | One ranking for plugin and theme directories. |
| `ThemeColor` (adds `hueSaturationLightness`), `AccentLegibility` (one `smallestMix`), `ThemeContrastGuard`, `ThemeProbeReading`, `ThemeModeTokens` (nested groups), `ThemeTokenGroup` | Theme decisions, all pure. |
| `CommunityPluginMarkdownRendering`, `CommunityPluginEditorChange` | One file each. |

**GraphiteUI**

| Type | Single responsibility |
| --- | --- |
| `CommunityPluginSession` | One open vault's plugin runtime. Created by `WorkspaceModel` at vault open with narrow capabilities, released at close. Holds the phase enum and its parts. |
| `CommunityPluginRuntimeConnection` (behind `CommunityPluginRuntimeChannel`, a protocol with one `send` and one incoming stream) | WebKit page, page load, timeouts, typed send and receive. The protocol exists so that the session's logic can run in unit tests with a scripted channel. |
| `CommunityPluginContributions` | Value of what plugins registered; replaced whole. |
| `CommunityPluginPackages` | Inventory, enabled list, load outcomes, consent (through `CommunityPluginDeviceStorage`), install and uninstall outcomes. |
| `CommunityPluginEditorBridge` | Snapshots, plugin edits, typing chain, paste and drop. |
| `CommunityPluginSurfaces` | Panel, notices, menus, settings requests. |
| `CommunityPluginViewRegistry` | Views, live view, pictures and restore state; the only writer of plugin view state. |
| `CommunityPluginCopyCache` | Shown copies and the LRU of kept copies. |
| `CommunityPluginPageStyles` | Page styles and body presentation; theme push; `appearance.setConfig`. |
| `ThemeTokenResolver` | Unchanged role; injected cache location; one shared timeout primitive. |
| Views | Each receives only the part it shows, and each event calls one intent method. |

**Seams and why each exists.**
- `HTTPDownloading`: installers and network requests have no tests (DIP-PLUGIN-02).
- `CommunityPluginRuntimeChannel`: the session is untestable without WebKit (SRP-PLUGIN-01).
- `CommunityPluginDeviceStorage`: hosted tests touch the real keychain and `UserDefaults` (DIP-PLUGIN-01).

No other protocol is needed. The workspace capabilities can be closures or one small protocol each where tests substitute them.

### Ordered steps (each leaves the app building and behaving the same, except where a step names the bug it fixes)

1. **Typed operations.** Introduce `CommunityPluginHostOperation` and `CommunityPluginRuntimeOperation` with raw values equal to today's strings. Switch the three Swift switches to the enums. Unknown incoming operations answer `unknownOperation` (OCP-PLUGIN-01). Generate `community-plugin-operations.js` and use its constants in the runtime.
2. **Shared bridge contract.** Write the JSON contract fixture and run it against `CommunityPluginVaultBridge` (Swift) and `test-vault-host.js` (Node). Align the Node host to production on the seven differences in LSP-PLUGIN-01.
3. **Typed store errors.** `VaultStore` throws `alreadyExists`/`missing`; the bridge maps by case (CC-PLUGIN-05). The contract fixture from step 2 proves the kinds unchanged.
4. **One timeout primitive.** Add `withTimeout`, used by `send(_:timeout:)` and `ThemeTokenResolver`, cancelling the loser (CC-PLUGIN-03). Name every timeout in `CommunityPluginTimeouts` (CC-PLUGIN-09). Give `plugin.load` a named timeout, so a hanging `onload` marks only that plugin failed and loading continues (fixes BUG-PLUGIN-02).
5. **Contributions value.** `receiveNotification` decodes the `*.changed` payloads into `CommunityPluginContributions`; `stopRuntime` assigns `.empty` (SRP-PLUGIN-02, OCP-PLUGIN-02).
6. **Phase enum.** Replace `isRuntimeRunning`, `isPageLoaded`, `pageLoadFailure` and the identity checks with `CommunityPluginRuntimePhase`. A start during `.stopping` awaits the stop and then starts (fixes BUG-PLUGIN-01). Keep `isRuntimeRunning` as a computed property for views until step 9.
7. **View registry.** Extract `CommunityPluginViewRegistry`. It ignores `views.changed` while the phase is `.stopping` and never persists a layout during a stop (fixes BUG-PLUGIN-06). The `WorkspaceModel` extension stops writing host fields (SRP-PLUGIN-04).
8. **Remaining parts.** Extract the editor bridge, surfaces, copy cache, page styles and vault change forwarder, one per commit. Each extraction moves state and methods unchanged.
9. **Session.** Introduce `CommunityPluginSession` with the runtime channel and device storage injected by the composition root. `WorkspaceModel` holds `communityPluginSession: CommunityPluginSession?`. Views receive the parts they show (ISP-PLUGIN-01, ISP-PLUGIN-02).
10. **Rename outcome.** `WorkspaceModel.move` returns `MoveOutcome`, and `workspace.renameFile` answers from it with no polling (fixes BUG-PLUGIN-03, CC-PLUGIN-02). `MarkdownSession.insertionsApplied()` replaces the two insertion polls.
11. **Secret store.** Distinguish `errSecItemNotFound` from other statuses. `setSecret` refuses to write over an item it could not read (fixes BUG-PLUGIN-05).
12. **Bases view updates.** Base the update on the whole message, by comparing a hash of `basesMessage(result)` or an `Equatable` result (fixes BUG-PLUGIN-04).
13. **Installers.** Extract `ObsidianReleaseDownloader` and `HTTPDownloading`; stage installs or write the manifest last (CC-PLUGIN-07); move install flows out of views into installation models (SRP-PLUGIN-03).
14. **Copy page as resources.** Move its HTML and JavaScript to resource files, pass one options object, add jsdom tests (CC-PLUGIN-04).
15. **Single theme vocabulary.** Pass probe key, callout and token lists from Swift to the probe (OCP-PLUGIN-03). Nest `ThemeModeTokens` groups with `ThemeTokenGroup` (3.2), and bump `defaultLayerVersion` in the same commit.
16. **Off-main bridge requests.** Send bridge requests as JSON text and decode them off the main actor (CC-PLUGIN-06).
17. **Tidying.** Split files (SRP-PLUGIN-05, SRP-PLUGIN-06), rename (CC-PLUGIN-12), rewrite comments (CC-PLUGIN-10), share duplicated helpers (CC-PLUGIN-08), prune the token cache (CC-PLUGIN-14), and read network responses in chunks (CC-PLUGIN-13).

### Behaviour that must be preserved

| ID | Invariant | Evidence | Test idea |
| --- | --- | --- | --- |
| PLUGIN-INV-01 | `community-plugins.json` is written as `[\n  "a",\n  "b"\n]` (two-space indent, slashes unescaped), and `[]` when empty | [CommunityPluginList.swift:41-48](../../../Sources/GraphiteCore/CommunityPluginList.swift#L41-L48) | Golden bytes for 0, 1 and 2 identifiers, including one with `/` and one with non-ASCII. |
| PLUGIN-INV-02 | An update merges with the file as it is now; an unchanged list keeps the file's bytes; a vault without the file gets one only when a plugin is turned on | [CommunityPluginList.swift:60-77](../../../Sources/GraphiteCore/CommunityPluginList.swift#L60-L77) | Existing test [CommunityPluginTests.swift:77-89](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L77-L89); add: turning off a plugin in a vault without the file creates nothing. |
| PLUGIN-INV-03 | A `community-plugins.json` that is not a JSON array is never overwritten; non-string entries are ignored on read | [CommunityPluginList.swift:18-27](../../../Sources/GraphiteCore/CommunityPluginList.swift#L18-L27) | Write `{}`, try to enable, assert a thrown error and unchanged bytes. |
| PLUGIN-INV-04 | Enabling appends at the end; order of existing entries is kept | [CommunityPluginList.swift:32-38](../../../Sources/GraphiteCore/CommunityPluginList.swift#L32-L38) | Enable `c` in `[a, b]` gives `[a, b, c]`; re-enabling `a` changes nothing. |
| PLUGIN-INV-05 | Install writes only `main.js`, `manifest.json` and `styles.css` under `.obsidian/plugins/<manifest id>/`; never `data.json`; a release without `styles.css` deletes the old one permanently | [CommunityPluginInstaller.swift:116-126](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L116-L126) | Scripted `HTTPDownloading`; pre-existing `data.json` keeps its bytes; old `styles.css` is gone. |
| PLUGIN-INV-06 | Release selection: the repository's `HEAD` manifest names the version; if its `minAppVersion` exceeds the provided API (`1.14.4`), the newest compatible version in `versions.json` is chosen, ties broken by text; the release manifest's id must equal the current manifest's and the directory's | [CommunityPluginInstaller.swift:84-115](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L84-L115), [:132-144](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L132-L144), [CommunityPluginInventory.swift:8](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L8) | Table test over scripted responses: newer `minAppVersion`, missing `versions.json` (404), mismatched id. |
| PLUGIN-INV-07 | Download addresses: `https://raw.githubusercontent.com/<owner/name>/HEAD/<file>` and `https://github.com/<owner/name>/releases/download/<version>/<file>`; directories at `obsidianmd/obsidian-releases/HEAD/community-plugins.json` and `community-css-themes.json` | [CommunityPluginInstaller.swift:44](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L44), [:86](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L86), [:106](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L106); [ObsidianThemes.swift:127](../../../Sources/GraphiteCore/ObsidianThemes.swift#L127), [:147](../../../Sources/GraphiteCore/ObsidianThemes.swift#L147), [:155](../../../Sources/GraphiteCore/ObsidianThemes.swift#L155) | Record the requested URLs in the scripted downloader and compare. |
| PLUGIN-INV-08 | Size caps: manifest 256 KiB, plugin directory 16 MiB, `versions.json` 1 MiB, `main.js` 48 MiB, `styles.css` 8 MiB, theme 8 MiB, snippet 1 MiB, theme manifest 64 KiB, theme directory 8 MiB, bridge transfer 64 MiB, network response 64 MiB, scheme resource 256 MiB, secrets 1 MiB | [CommunityPluginManifest.swift:24](../../../Sources/GraphiteCore/CommunityPluginManifest.swift#L24), [CommunityPluginInstaller.swift:45-46](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L45-L46), [CommunityPluginInventory.swift:124-125](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L124-L125), [ObsidianThemes.swift:54-55](../../../Sources/GraphiteCore/ObsidianThemes.swift#L54-L55), [:128-129](../../../Sources/GraphiteCore/ObsidianThemes.swift#L128-L129), [CommunityPluginVaultBridge.swift:22](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L22), [CommunityPluginNetworkRequest.swift:13](../../../Sources/GraphiteCore/CommunityPluginNetworkRequest.swift#L13), [CommunityPluginWebContent.swift:23](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L23), [CommunityPluginSecretStore.swift:10](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L10) | One boundary test per cap: exactly at the cap succeeds, one byte over fails with `tooLarge`/`oversized`. |
| PLUGIN-INV-09 | Identifier rule: non-empty, at most 128 UTF-8 bytes, not `.`/`..`, no leading dot, no `/`, `\`, `:`, control characters or newlines; repository is exactly `owner/name` of `[A-Za-z0-9._-]`, neither part `.` or `..` | [CommunityPluginManifest.swift:50-54](../../../Sources/GraphiteCore/CommunityPluginManifest.swift#L50-L54), [CommunityPluginInstaller.swift:64-70](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L64-L70) | Existing tests [CommunityPluginTests.swift:49-56](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L49-L56), [:234-240](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L234-L240); add the 128-byte boundary. |
| PLUGIN-INV-10 | Version order: leading `v` ignored, build metadata dropped, missing parts are 0, a pre-release sorts before its release, pre-release identifiers ordered by semantic versioning | [CommunityPluginManifest.swift:60-111](../../../Sources/GraphiteCore/CommunityPluginManifest.swift#L60-L111) | Existing tests [CommunityPluginTests.swift:57-64](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L57-L64), [:214-233](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L214-L233). |
| PLUGIN-INV-11 | Compatibility: `isDesktopOnly` and a newer `minAppVersion` block loading; a missing `main.js` blocks; `require` of Node/Electron modules (list of 33 names, `node:` prefix stripped) or unknown modules is reported but does not block; the 10 vendored CodeMirror/Lezer modules are not reported | [CommunityPluginInventory.swift:40-85](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L40-L85) | Existing test [CommunityPluginTests.swift:90-128](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L90-L128); add a `node:fs` case. |
| PLUGIN-INV-12 | Consent key `GraphiteCommunityPluginsTurnedOn.<vault UUID>` in user defaults; removed when the vault leaves the list | [CommunityPluginHost.swift:287](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L287), [:301-303](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L301-L303) | With injected device storage: turn on, forget the vault, assert the key is gone. |
| PLUGIN-INV-13 | Keychain item: generic password, service `Graphite community plugin secrets`, account = vault UUID string, value = JSON `[String: String]`, accessibility `AfterFirstUnlockThisDeviceOnly`, data protection keychain unless the Mac process lacks the entitlement; an empty secret removes the entry | [CommunityPluginSecretStore.swift:8](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L8), [:22-38](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L22-L38), [:52-63](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L52-L63) | Existing test [CommunityPluginSecretStoreTests.swift:9-26](../../../Tests/GraphiteAppleTests/CommunityPluginSecretStoreTests.swift#L9-L26); add a test that a read failure refuses the write. |
| PLUGIN-INV-14 | Web storage is `WKWebsiteDataStore(forIdentifier: vault UUID)`; removed when the vault leaves the list | [CommunityPluginHost.swift:373](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L373), [:304-309](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L304-L309) | Existing hosted test [CommunityPluginHostTests.swift:155-164](../../../App/Tests/CommunityPluginHostTests.swift#L155-L164). |
| PLUGIN-INV-15 | URL scheme `graphite-plugins`; page at `graphite-plugins://runtime/index.html`; vault resources at `graphite-plugins://vault/<percent-encoded vault path>`, files only, never folders; `Access-Control-Allow-Origin: graphite-plugins://runtime` | [CommunityPluginWebContent.swift:16-20](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L16-L20), [:55-61](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L55-L61), [:88-106](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L88-L106) | Unit test of `location(for:)`: `100%.png` decoded once, `../` refused, a folder refused. |
| PLUGIN-INV-16 | Message handler name `graphitePlugins` in the page world; Graphite calls `GraphitePluginRuntime.receive(message)`; copies use handler `graphiteCodeBlock` in the default client world | [CommunityPluginHost.swift:375](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L375), [:842](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L842), [CommunityPluginReadingBlocks.swift:402](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L402), [:768](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L768) | Assert the names against the generated JavaScript constants (step 1). |
| PLUGIN-INV-17 | All 83 operation names and the 16 failure kinds keep their exact spelling | Section 4, OCP-PLUGIN-01 and LSP-PLUGIN-03 | The generated constants file is compared with a golden list in both Swift and Node tests. |
| PLUGIN-INV-18 | Answer shapes: stat `{isFolder, size (0 for folders), modified, created}` with times in milliseconds since 1970, rounded; revision `{digest, size}`; failure `{failure: {kind, message}}`; listing `{entries, isTruncated}`; folder listing `{files, folders}` sorted | [CommunityPluginVaultBridge.swift:133-138](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L133-L138), [:172](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L172), [:323-334](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L323-L334), [:352-368](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L352-L368) | Contract fixture (step 2) with golden JSON per operation. |
| PLUGIN-INV-19 | `vault.list` leaves out hidden items and symbolic links and stops at 250,000 entries with `isTruncated: true` only when more exist | [CommunityPluginVaultBridge.swift:18-20](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L18-L20), [:115-139](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L115-L139) | Existing test [CommunityPluginTests.swift:129-140](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L129-L140); add a cap test with an injected cap. |
| PLUGIN-INV-20 | Text reads drop a leading UTF-8 BOM and replace invalid bytes; text writes keep an existing BOM unless the text starts with U+FEFF | [CommunityPluginVaultBridge.swift:214-217](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L214-L217), [:250-254](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L250-L254) | Existing test [CommunityPluginTests.swift:141-149](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L141-L149). |
| PLUGIN-INV-21 | Write expectations: `absent`, `revision` (requires a revision), `replace` (current revision, or absent); anything else is `invalidData` | [CommunityPluginVaultBridge.swift:224-236](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L224-L236) | Existing test [CommunityPluginTests.swift:151-164](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L151-L164); add the unknown-kind case. |
| PLUGIN-INV-22 | Remove methods `system`→system trash, `local`→vault trash, `permanent`→delete, `vaultSetting`→the vault's "Deleted files" setting; outcomes `systemTrash`, `vaultTrash` + `trashPath`, `deleted`; `isFolderExpected` mismatch fails `isFolder`/`notFolder`; non-recursive non-empty folder fails `notEmpty` | [CommunityPluginVaultBridge.swift:258-283](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L258-L283) | Existing test [CommunityPluginTests.swift:171-185](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L171-L185); add `system` and mismatch cases. |
| PLUGIN-INV-23 | A plugin's edit applies only to the open note whose text equals the snapshot it was given; it is one minimal edit, never splitting a surrogate pair, selection clamped to the new text; refused in reading view (`readOnly`) | [CommunityPluginEditorChange.swift:12-32](../../../Sources/GraphiteCore/CommunityPluginEditorChange.swift#L12-L32), [CommunityPluginHost.swift:757-793](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L757-L793) | Existing tests [CommunityPluginTests.swift:189-205](../../../Tests/GraphiteCoreTests/CommunityPluginTests.swift#L189-L205), hosted [CommunityPluginHostTests.swift:105-139](../../../App/Tests/CommunityPluginHostTests.swift#L105-L139); add a session-level unit test with the scripted channel. |
| PLUGIN-INV-24 | Start order: page load → `runtime.start` → `plugin.load` per enabled plugin in name order → `plugins.layoutReady` → restore views → active document | [CommunityPluginHost.swift:401-419](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L401-L419) | Scripted channel records the sequence of outgoing operations. |
| PLUGIN-INV-25 | Timeouts and debounces: menus 2 s, typing 4 s, taps and most fire-and-forget answers 5 s, block drawing 20 s, paste and drop 1.5 s, open-in-view 3 s, save-file-views 4 s, protocol links and Bases views 10 s, stop wait 2 s, theme measurement 15 s; vault changes 300 ms, page styles 100 ms, theme refresh 300 ms, appearance save 600 ms | Constants and literals cited in CC-PLUGIN-09 and Architecture claims in section 1 | One test per named constant once they live in `CommunityPluginTimeouts`, plus scripted-clock tests of the debounces. |
| PLUGIN-INV-26 | Typing: notes longer than 512 Ki UTF-16 units are not sent; changes are sent in order; suggestions are shown only for the latest revision | [CommunityPluginTyping.swift:25-60](../../../Sources/GraphiteUI/CommunityPluginTyping.swift#L25-L60) | Scripted channel delays answer 1; assert answer 2 is sent after it and only revision 2's items return. |
| PLUGIN-INV-27 | Caches: 64 kept copies, least recently drawn evicted; 8 editor snapshots; 4 notices (3 action buttons, 4,500 ms default, 6,000 ms for Graphite's own, ids prefixed `graphite-` never sent back); 5 runtime problems per plugin; 50 recent files sent | [CommunityPluginReadingBlocks.swift:213-220](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L213-L220), [CommunityPluginHost.swift:743](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L743), [:1017](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1017), [:1024-1028](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1024-L1028), [:1065-1068](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1065-L1068), [:1084](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1084), [:473](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L473) | Unit tests on the extracted parts. |
| PLUGIN-INV-28 | Network requests: only `http`/`https`; method uppercased; `Content-Type` from `contentType`; body base64; answer `{status, headers (lowercased names), bodyBase64}` | [CommunityPluginNetworkRequest.swift:22-54](../../../Sources/GraphiteCore/CommunityPluginNetworkRequest.swift#L22-L54) | Scripted downloader; `file://` refused; header names lowercased. |
| PLUGIN-INV-29 | `appearance.json`: only owned keys whose values changed are written; fonts as unquoted comma lists; `enabledCssSnippets` laid out as `JSON.stringify(settings, null, 2)` lays out a list; unknown keys keep their bytes; a non-object file is never overwritten; plugins may set only the 7 whitelisted keys | [ObsidianAppearance.swift:162-208](../../../Sources/GraphiteCore/ObsidianAppearance.swift#L162-L208), [CommunityPluginThemes.swift:65-87](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L65-L87) | Existing tests [ObsidianAppearanceTests.swift:97-215](../../../Tests/GraphiteCoreTests/ObsidianAppearanceTests.swift#L97-L215); add a plugin `setConfig` of an unlisted key changing nothing. |
| PLUGIN-INV-30 | Theme and snippet paths: `.obsidian/themes/<name>/theme.css` (+ `manifest.json`), `.obsidian/snippets/<name>.css`; names are one path component without a leading dot; the installed theme's manifest `name` must equal the directory entry's name | [ObsidianThemes.swift:50-79](../../../Sources/GraphiteCore/ObsidianThemes.swift#L50-L79), [:164-169](../../../Sources/GraphiteCore/ObsidianThemes.swift#L164-L169) | Existing test [ObsidianAppearanceTests.swift:216-243](../../../Tests/GraphiteCoreTests/ObsidianAppearanceTests.swift#L216-L243); add the name-mismatch install case. |
| PLUGIN-INV-31 | Theme cache: file `Caches/Graphite/ThemeTokens/<fingerprint>.json`; fingerprint = lowercase hex SHA-256 over `v<defaultLayerVersion>`, theme name, style sheets, body classes, body style and accent style, each followed by one zero byte; `defaultLayerVersion` (5) changes whenever the default layer, the probe or the token shape changes | [ThemeTokenResolver.swift:20-27](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L20-L27), [:38](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L38), [:178-196](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L178-L196) | Golden fingerprint for fixed inputs; existing cache test [ThemeTokenResolverTests.swift:88](../../../Tests/GraphiteUITests/ThemeTokenResolverTests.swift#L88). |
| PLUGIN-INV-32 | Probe vocabulary: the 159 probe keys, 27 callout types and 11 Prism token classes match between `theme-probe.js` and `ThemeProbeReading`; a value equal to the default layer's reads as nil | [theme-probe.js:8-12](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L8-L12), [:83-171](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L83-L171), [VaultThemeTokens.swift:281-381](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L281-L381) | A test that runs the probe page once and asserts every key `ThemeProbeReading` reads is present. |
| PLUGIN-INV-33 | Accent sent to themes as hue with one decimal, saturation and lightness as percentages with one decimal, both to the plugins' page (`{hue, saturation, lightness}`) and to the resolver (`--accent-h: H; --accent-s: S%; --accent-l: L%; `) | [CommunityPluginThemes.swift:26-28](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L26-L28), [:90-108](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L90-L108), [WorkspaceTheme.swift:38-40](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L38-L40) | Existing test [CommunityPluginThemeTests.swift:7](../../../Tests/GraphiteUITests/CommunityPluginThemeTests.swift#L7); add the CSS string's golden text. |
| PLUGIN-INV-34 | Contrast targets: 4.5:1 text, 3:1 large text, 7:1 with Increase Contrast; a theme highlight with hue 180–255° is replaced; callout tint counts only between 0.03 and 0.6 and more than 0.02 from 0.1 | [AccentLegibility.swift:9-11](../../../Sources/GraphiteCore/AccentLegibility.swift#L9-L11), [VaultThemeTokens.swift:85-123](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L85-L123), [:360-361](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L360-L361) | Existing tests in [AccentLegibilityTests.swift](../../../Tests/GraphiteCoreTests/AccentLegibilityTests.swift) and [VaultThemeTokensTests.swift](../../../Tests/GraphiteCoreTests/VaultThemeTokensTests.swift); add tint boundary values. |
| PLUGIN-INV-35 | Copy pages run no page script, use one shared non-persistent data store, and follow no navigation after the first load | [CommunityPluginReadingBlocks.swift:722-726](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L722-L726), [:755-762](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L755-L762) | Inspect the configuration of a built display web view in a unit test. |
| PLUGIN-INV-36 | The runtime page is never replaced by navigation; only `http`, `https` and `mailto` link activations open outside the app | [CommunityPluginWebContent.swift:139-152](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L139-L152) | Unit test of the policy function with fake navigation actions after extracting it as a pure decision. |
| PLUGIN-INV-37 | Saved plugin views (type and state JSON up to 64 KiB, per tab and for the sidebar) survive a runtime stop and are reopened after `plugins.layoutReady` | [CommunityPluginViews.swift:247-311](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L247-L311), [community-plugin-runtime-workspace.js:808-812](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L808-L812) | Regression test for BUG-PLUGIN-06: open a view, switch vaults, switch back, assert the view's tab is restored. |

### Tests that become possible once the seams exist

- **Session lifecycle without WebKit** (scripted `CommunityPluginRuntimeChannel`): start during stop (BUG-PLUGIN-01), a hanging `plugin.load` (BUG-PLUGIN-02), the start order (PLUGIN-INV-24), stop resetting contributions (SRP-PLUGIN-02), unknown incoming operation answered `unknownOperation`.
- **Bridge contract parity**: one fixture, run in Swift against `CommunityPluginVaultBridge` and in Node against `test-vault-host.js` (LSP-PLUGIN-01).
- **Installers and network** (scripted `HTTPDownloading`): release selection, 404 handling, id mismatches, staged writes surviving a failed second write, response caps.
- **Device storage** (fake `CommunityPluginDeviceStorage`): consent per vault, forgetting a vault, a secret read failure refusing the write (BUG-PLUGIN-05), all hermetic.
- **Rename outcome**: `workspace.renameFile` onto a taken name answers `exists` (BUG-PLUGIN-03).
- **Bases update**: a formula value change with the same rows sends `basesView.update` (BUG-PLUGIN-04).
- **Copy page script** in jsdom: morph keeps a focused field's value; long press posts `contextmenu`; a drag past 6 px posts `gesture` phases.
- **Theme vocabulary**: every key read by `ThemeProbeReading` is produced by the probe (PLUGIN-INV-32).

## 8. Appendix: raw metrics

### Reconnaissance numbers, checked

| Metric (reconnaissance) | Value | Check |
| --- | --- | --- |
| Files / physical / code lines | 27 / 6,665 / 4,968 | File list confirmed; every file read in full. |
| Functions over 40 code lines | `receiveNotification` 118, `ThemeProbeReading.tokens` 96, `startIfNeeded` 59, `stopRuntime` 51, `CommunityPluginInstaller.install` 43, `answerHostOperation` 41 | Start lines confirmed by reading ([CommunityPluginHost.swift:936](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L936), [VaultThemeTokens.swift:281](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L281), [CommunityPluginHost.swift:352](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L352), [:506](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L506), [CommunityPluginInstaller.swift:84](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L84), [CommunityPluginHost.swift:870](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L870)). |
| Types over 300 code lines | `CommunityPluginHost` 771 | Confirmed; with its five extension blocks (506 physical lines) the type is larger still. |
| Files over 400 code lines | `CommunityPluginHost.swift` 875, `CommunityPluginReadingBlocks.swift` 437, `CommunityPluginViews.swift` 429 | Confirmed. `CommunityPluginReadingBlocks.swift` also holds 251 lines of JavaScript and 28 of HTML/CSS in strings, which the code-line count excludes. |
| `try?` | 109 | Not re-counted scope-wide. In the 17 `CommunityPlugin*.swift` files, 87 lines contain `try?` (grep `try\?`). |
| `Task.sleep` / `sleep` | 12 | Confirmed by reading: 8 in `CommunityPluginHost.swift`, 1 each in `CommunityPluginThemes.swift`, `ThemeTokenResolver.swift`, `WorkspaceAppearance.swift` and `WorkspaceTheme.swift`. |
| `.shared` | 6 | Confirmed: 3 `URLSession` defaults, `UIApplication.shared`, and `NSWorkspace.shared` twice (link opener, motion). |
| `static var` | 5 | Confirmed; all five are computed properties (`runtimePageAddress`, `resourcePathPrefix`, `shell`, `GraphiteMotion.isReduced`, `cacheFolder`). The area has no static mutable state. |
| `UserDefaults` | 3 | Confirmed (all consent). |
| `FileManager.default` | 14 | Confirmed: 9 in `CommunityPlugin*.swift`, 3 in `ObsidianThemes.swift`, 2 in `ThemeTokenResolver.swift`. |
| `URLSession` | 5 | Confirmed. |
| `default:` in switch | 16 | Not re-counted. The three message switches each end in `default:` (OCP-PLUGIN-01), as do the theme setConfig switch ([CommunityPluginThemes.swift:83](../../../Sources/GraphiteUI/CommunityPluginThemes.swift#L83)) and the copy-page message switch ([CommunityPluginReadingBlocks.swift:712](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L712)). |
| `[String: Any]` | 100 | Line count: 96 lines (grep `\[String: Any\]` over `CommunityPlugin*.swift` and `ThemeTokenResolver.swift`); some lines hold two occurrences, which explains the difference. |
| `Task { }` | 54 | 44 lines in `Sources/GraphiteUI/CommunityPlugin*.swift` (grep `Task(\.detached)?(\(priority: [.a-zA-Z]+\))? \{`); the rest are in the resolver, workspace appearance and theme files, and theme settings. |
| Commits per file (top) | `CommunityPluginHost.swift` 21, then 8 each for views, reading blocks and presentation | Taken as given (git history is outside the snapshot tools). |

### Counts made for this audit

| Count | Value | Method |
| --- | ---: | --- |
| `CommunityPluginHost` stored properties | 63 | Read [CommunityPluginHost.swift:166-291](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L166-L291). |
| `CommunityPluginHost` members | 88 | 49 in the main block, 9 in menus, 5 in themes, 4 in typing, 5 in reading blocks, 16 in views (counted by reading). |
| Host properties writable from outside | 21 | Properties without `private(set)` or `private`, by reading. |
| Fields reset by `stopRuntime` / runtime fields it misses | 35 / 13 | Read [:515-557](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L515-L557) against the property list. |
| Reads of `isRuntimeRunning` | 35 | grep `isRuntimeRunning` over `Sources/GraphiteUI/CommunityPlugin*.swift`: 38 lines minus the declaration and two assignments. |
| `WorkspaceModel` members the host uses | 24 | By reading every `workspace.` use in the six host files. |
| Types that hold the whole host | 20 | grep `host: CommunityPluginHost` in `Sources/GraphiteUI` (coordinators included). |
| JavaScript→Swift operation names | 44 | Cases of the three Swift switches (9 + 9 + 26). |
| JavaScript call sites of those operations | 70 in 9 files | grep `hostBridge\.(send|notify)\('([a-zA-Z.]+)'` over `Resources/CommunityPluginRuntime/*.js`. |
| Swift→JavaScript operation names | 39 | Every `"operation":` literal in the six host files, by reading. |
| Failure kinds | 16 | 12 in the bridge (`unknownOperation`, `missing`, `isFolder`, `notFolder`, `tooLarge`, `invalidData`, `notEmpty`, `exists`, `conflict`, `outsideVault`, `invalidPath`, `failed`) plus 4 in the host (`readOnly`, `network`, `cancelled`, `unavailable`). |
| Node test host differences from the bridge | 7 | Table in LSP-PLUGIN-01. |
| `ThemeModeTokens` stored properties | 53 | Read [VaultThemeTokens.swift:130-196](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L130-L196). |
| Theme probe keys | 68 forms, 159 keys | Read `readValues` in [theme-probe.js:83-171](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js#L83-L171): 10 body/text keys, 11 per heading × 6, 1 per callout type × 27, 45 other single keys, 1 per token class × 11. |
| Literal durations and caps in `CommunityPluginHost.swift` | 20 | By reading (CC-PLUGIN-09). |
| Sleep-polling loops | 4 | By reading (CC-PLUGIN-02). |
| Hand-made first-outcome primitives | 3 | `FirstOutcome`, `SingleResumption`, `MeasurementOutcome`+`MeasurementTasks`. |
| Embedded code in strings | 251 JavaScript + 28 HTML/CSS lines, plus 3 short snippets | By reading (CC-PLUGIN-04). |
| Tests covering the area | Core: `CommunityPluginTests` 20, `ObsidianAppearanceTests` 14, `VaultThemeTokensTests` 6, `AccentLegibilityTests` 7; UI (macOS): `ThemeTokenResolverTests` 4, `CommunityPluginThemeTests` 1; Apple: `CommunityPluginSecretStoreTests` 1; hosted iPad: `CommunityPluginHostTests` 11 | grep `func test` in each file. The secret store and hosted tests use the real keychain and `UserDefaults` (not hermetic). No test covers `install`, `directory`, `perform`, `stopRuntime` ordering, or the layout after a runtime stop. |

### Findings tally

| Severity | Count | IDs |
| --- | ---: | --- |
| High | 5 | SRP-PLUGIN-01, OCP-PLUGIN-01, LSP-PLUGIN-01, ISP-PLUGIN-01, CC-PLUGIN-01 |
| Medium | 17 | SRP-PLUGIN-02, -03, -04; OCP-PLUGIN-02, -03; LSP-PLUGIN-02, -03; ISP-PLUGIN-02, -03; DIP-PLUGIN-01, -02; CC-PLUGIN-02, -03, -04, -05, -06, -07 |
| Low | 12 | SRP-PLUGIN-05, -06; OCP-PLUGIN-04; LSP-PLUGIN-04; DIP-PLUGIN-03; CC-PLUGIN-08 to -14 |
| Bugs | 6 | BUG-PLUGIN-01 to -06 (five traced, one partly traced) |
| Invariants | 37 | PLUGIN-INV-01 to -37 |

## 9. Since the snapshot

Delta audit of 2026-10-19 at `fff794b` (main), against `FR-01` to `FR-108`. Commits: `4489db2` (plugin start, stop, rename and views), `877045a` (unreadable vault settings show an error), `0c074d9` (the consent key on injected preferences). Invariants touched: SEC-03, P-14.

### New findings

#### CC-PLUGIN-15 A plugin rename learns its outcome by polling a dictionary added to `WorkspaceModel`
- **Severity:** Medium
- **Rule:** `FR-12`, `FR-65`, `FR-03`, `FR-72`
- **Evidence:** `@ObservationIgnored var answeredMoveOutcomes: [VaultPath: FileMoveOutcome]` ([WorkspaceModel.swift:47](../../../Sources/GraphiteUI/WorkspaceModel.swift#L47)) is written when the person answers or a queued move finishes ([WorkspaceFileManagement.swift:176](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L176), [:181](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L181)); the host polls every 200 ms while the move is pending and every 100 ms for up to 10 s for the answer ([CommunityPluginHost.swift:997-1005](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L997-L1005)); entries for moves the person starts stay until the vault closes ([WorkspaceModel.swift:358](../../../Sources/GraphiteUI/WorkspaceModel.swift#L358)). Introduced in `4489db2`.
- **Why it matters:** the outcome travels through a shared mutable field: a second rename of the same path overwrites it, the plugin waits up to 300 ms longer than needed, and the workspace root gains plugin state reset by hand.
- **Fix direction:** `move` returns the final `FileMoveOutcome` from an `async` call that resumes on the answer; the dictionary goes.

#### CC-PLUGIN-16 A plugin's Bases view JSON-encodes the whole query result on every body evaluation
- **Severity:** Medium
- **Rule:** `FR-69`, `FR-104`, `FR-103`
- **Evidence:** `.onChange(of: Self.updateKey(for: result))` ([CommunityPluginViews.swift:552](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L552)) builds `basesMessage` for every row and serializes it with sorted keys ([:530-534](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L530-L534)) on each `body`; `updateBasesView` builds the same message again when the key changes ([:127](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L127), [:137](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L137)). Introduced in `4489db2`.
- **Why it matters:** for a large base, every redraw costs a full build and encode on the main actor even when nothing changed.
- **Fix direction:** an `Equatable` `BaseQueryResult` or a query revision number; build the message only when it is sent.

#### CC-PLUGIN-17 `isRuntimeRunning` answers true while the runtime is stopping
- **Severity:** Low
- **Rule:** `FR-81`, `FR-33`
- **Evidence:** `var isRuntimeRunning: Bool { runtimePhase != .stopped }` ([CommunityPluginHost.swift:219-220](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L219-L220)) is read on 42 lines, while the new code writes `runtimePhase == .running` where it means running ([:664](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L664), [:1154-1155](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1154-L1155)). Introduced in `4489db2`.
- **Fix direction:** rename it `hasRuntime`.

#### CC-PLUGIN-18 `pluginLoadTimeout` is a mutable production field that only tests change
- **Severity:** Low
- **Rule:** `FR-32`, `FR-78`
- **Evidence:** `@ObservationIgnored var pluginLoadTimeout = Duration.seconds(30)` ([CommunityPluginHost.swift:607-608](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L607-L608)), set only by `CommunityPluginHostRuntimeTests.swift:133`. Introduced in `4489db2`.
- **Fix direction:** a named constant, and a timeout policy injected through the initializer for the test.

### State changes of earlier findings
- `CC-PLUGIN-01`: Open → **Partly fixed**. `RuntimePhase` with `stopping(startsAgain:)` replaces the flag ([CommunityPluginHost.swift:208-218](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L208-L218)); `isPageLoaded`, `pageLoadFailure` and four `webView === pluginWebView` checks remain.
- `CC-PLUGIN-02`: Open → **Partly fixed**. The rename result comes from `FileMoveOutcome`; all four loops still sleep-poll.
- `CC-PLUGIN-09`: Open → **Partly fixed**. `renameAnswerDeadline` and `pluginLoadTimeout` are named; the 200 ms and 100 ms polls and the 2 s stop wait are literals.
- `LSP-PLUGIN-02`: Open → **Partly fixed** (item 2 of 7): an unreadable `community-plugins.json` now throws ([CommunityPluginList.swift:63](../../../Sources/GraphiteCore/CommunityPluginList.swift#L63)).
- `LSP-PLUGIN-03`: Open → **Partly fixed**. The timeout is a typed `CommunityPluginRuntimeError.didNotAnswerInTime`; runtime failures still become `GraphiteError.unavailable` and a non-object answer `[:]`; the new error carries an English sentence (`FR-55`, `FR-64`).
- `CC-PLUGIN-03`: **Worse by one** unowned task ([CommunityPluginViews.swift:23](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L23)).
- `CC-PLUGIN-11`: **Worse**: `stopRuntime` grows to 55 code lines, `startIfNeeded` to about 64.
- `SRP-PLUGIN-02`: **Worse**: `hasRestoredViews = false` and `isTurnedOnForVault = false` are each reset in two places.
- `SRP-PLUGIN-04`: **Worse**: a new `WorkspaceModel` extension method closes and opens tabs for the host ([CommunityPluginViews.swift:210-223](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L210-L223)).
- `DIP-PLUGIN-01`: unchanged, extended: `CommunityPluginHost(defaults: = .standard)` and `forgetVault(_:defaults: = .standard)` serve only tests, since production always passes the store; their comment states a plan ("Phase 2 removes it") rather than a rule (`FR-80`).

### Patterns to keep
- The runtime's lifecycle is an enum (`RuntimePhase`) with a queued restart, so "a start during a stop" is data.
- The rename answer comes from an exhaustive switch over `FileMoveOutcome` and `FileMoveRefusal` with no `default:` ([CommunityPluginHost.swift:984-1015](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L984-L1015)).

### Changes merged after 9040705 (5aae924)

#### CC-PLUGIN-19 Waiting plugin-view reveals outlive the runtime they belong to
- **Severity:** Low
- **Rule:** `FR-04`
- **Evidence:** `revealsAwaitingTheirView` ([CommunityPluginHost.swift:190](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L190), [:1049-1050](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L1049-L1050)) is missing from `stopRuntime`'s hand reset of about 25 fields ([:548-585](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L548-L585)); a reveal for a leaf that never lists stays queued (up to 16) across restarts and vault switches. Leaf identifiers carry a per-page timestamp, so a stale entry never matches: the cost is leaked state, not a wrong reveal. Introduced in `a724bd5`.
- **Fix direction:** keep the queue in the per-runtime value that `stopRuntime` replaces (`SRP-PLUGIN-02`).
