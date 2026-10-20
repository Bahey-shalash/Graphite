# Community plugin JavaScript runtime (RUNTIME)
Snapshot: b13dec3 (main, 2026-10-18).
Scope: `Sources/GraphiteUI/Resources/CommunityPluginRuntime/` without `Vendor/` (11 JavaScript files, 2 CSS files, `index.html`), 14 files, 8466 physical lines, 7287 code lines (method: blank and comment-only lines and string contents removed by the reconnaissance script; for JavaScript, non-blank lines not starting with a comment marker).

Link names in this document drop the common prefix: `foundation.js` is `community-plugin-runtime-foundation.js`, `dom-extensions.js` is `community-plugin-dom-extensions.js`, `runtime.css` is `community-plugin-runtime.css`, and so on.

| Principle | Verdict | Reason |
| --- | --- | --- |
| S | Weak | `plugins.js` holds about 18 responsibilities in one 1324-code-line closure with 28 message handlers; the global `GraphitePluginRuntime` namespace carries 50 members written from 11 files. |
| O | Mixed | 83 message names are string literals repeated by hand in the runtime, the Swift host and the Node test host; feature files join by mutating shared objects in script order. Obsidian's class hierarchy itself extends cleanly. |
| L | Mixed | The Node test host accepts editor changes production refuses; tests pin a `vault.changes` shape (`moves`, `stat`) production never sends; `Vault.config` and `Vault.getConfig` disagree. The ES5 class shim keeps `instanceof` exact. |
| I | Mixed | Messages are untyped dictionaries; 9 ad hoc fields are written onto leaves, views and the vault from other files. The large Obsidian-facing classes are mandated by Obsidian's API. |
| D | Mixed | The host transport is a clean, injected seam (the Node harness replaces it); 70 direct `hostBridge` call sites and 61 `runtime.app` lookups reach the globals from domain classes; one global prototype patch of `EventTarget`. |
| Clean code | Mixed | Names are explicit and most limits are named constants; 11 functions run over 40 lines (the longest 187), 81 lines exceed 160 characters, an error-text idiom is copied 15 times, and timers stand in for ordering in 6 places. |

## 1. Summary

**What the area does.** The runtime is Graphite's reimplementation of Obsidian's `obsidian` module and the browser environment Obsidian gives community plugins. `index.html` loads four vendored libraries and then eleven runtime scripts in a fixed order ([index.html:11-26](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/index.html#L11-L26)). Each script is an immediately invoked function that adds to one global namespace, `GraphitePluginRuntime`, and to the exported module object `obsidianModule` ([foundation.js:7-8](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L7-L8)). Its shape, in load order:

- `dom-extensions.js` adds Obsidian's helpers to DOM and built-in prototypes, never overwriting existing members.
- `foundation.js` holds the channel to the host (`hostBridge`), unsupported-feature reporting, `Events`, `Component` and Obsidian's utility functions.
- `vault.js` holds the file tree, the revision-checked `DataAdapter`, `Vault` and `FileManager`. `metadata.js` holds a Markdown scanner and `MetadataCache`.
- `workspace.js` holds the snapshot editor, leaves, views and `Workspace`. `interface.js` holds icons, notices, modals, setting controls, suggestion lists and menus. `settings.js` adds declarative settings. `bases.js` adds Bases values and views.
- `plugins.js` holds the module loader, registries, `Plugin`, `App` and the host-to-runtime message dispatcher.
- `reading.js` mirrors plugin-drawn blocks and views into Graphite's native surfaces. `host-connection.js` wires the WebKit message handler.

The two style sheets give Obsidian's CSS variables and classes.

**The three biggest problems.**
1. **A plugin's asynchronous editor edit lands in whatever note the person switched to** ([BUG-RUNTIME-01](#bug-runtime-01-a-plugins-asynchronous-edit-lands-in-the-note-the-person-switched-to)). One `SnapshotEditor` object is reused for every note. A plugin that keeps its `editor` across an `await` writes into the next note's text, and the host accepts the edit because the snapshot matches.
2. **No typed contract across the Swift boundary.** 44 runtime-to-host and 39 host-to-runtime operation names, plus every payload field, are literals maintained by hand in three places ([OCP-RUNTIME-01](#ocp-runtime-01-83-message-names-and-their-payloads-are-literals-kept-in-step-by-hand-in-three-places)). The Node test host already disagrees with production on `editor.apply` ([LSP-RUNTIME-01](#lsp-runtime-01-the-node-test-host-accepts-editor-changes-that-production-refuses)) and on `vault.changes` ([LSP-RUNTIME-02](#lsp-runtime-02-tests-pin-a-vaultchanges-shape-that-production-never-sends)).
3. **A global namespace used as a service locator and a cross-file mutable registry** ([SRP-RUNTIME-02](#srp-runtime-02-the-global-graphitepluginruntime-namespace-is-a-service-locator-and-a-shared-mutable-registry)). Later files fill in functions that earlier files call. Feature files register by mutating objects defined elsewhere, which ties correctness to script order, and `plugins.js` concentrates most of that coupling ([SRP-RUNTIME-01](#srp-runtime-01-pluginsjs-is-one-1324-code-line-closure-with-about-18-responsibilities)).

**The three best parts.**
1. **Revision-checked, serialized writes.** Every write states what it expects (`revision`, `replace` or `absent`). Writes to one path queue in order, `process` re-reads and retries on conflict, and a conflict is reported rather than overwritten ([vault.js:172-283](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L172-L283)). This is the runtime's implementation of OBJECTIVE.md's "never silently overwrite".
2. **A single injected transport and a hermetic Node harness.** The page connects through `hostBridge.transport` ([host-connection.js:13](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-host-connection.js#L13)). The harness loads the real scripts in `index.html` order into jsdom against a temporary vault folder ([runtime-harness.js:14-17](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L14-L17), [runtime-harness.js:95-106](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L95-L106)). 85 tests, 18 of them against real plugins built from source, exercise the production page.
3. **Honest unsupported features.** Missing APIs throw `UnsupportedFeatureError` and are reported once per plugin and feature ([foundation.js:95-110](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L95-L110)). Desktop modules are inert stand-ins that fail only when used ([plugins.js:145-169](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L145-L169)). Plugin code is attributed through blob addresses or `sourceURL`, with a probe for which works ([plugins.js:93-143](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L93-L143)).

**Earlier-pass claims.**

| Claim | Where | Holds? | Evidence |
| --- | --- | --- | --- |
| `Docs/SOLID.md` covers this area | SOLID.md | No: it predates the runtime (the runtime began 2026-10-10) and never mentions it | `grep -i "plugin\|web ?view" Docs/SOLID.md` finds one unrelated line (`Docs/SOLID.md:44` at b13dec3) |
| The runtime lives in `Resources/CommunityPluginRuntime`, its tests in Node | [Architecture.md:82-86](../../../Docs/Architecture.md#L82-L86) | Holds | [runtime-harness.js:12](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L12), [package.json:7](../../../Tests/CommunityPluginRuntimeTests/package.json#L7) |
| The default layer has no specificity, so a theme overrides every rule | [Architecture.md:282](../../../Docs/Architecture.md#L282) | Holds for `graphite-default-variables.css` (every rule is `:where(...)`); does not hold for the plugin page, which also loads `runtime.css` with `body {` and `body.theme-dark` rules | [runtime.css:226](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L226), [runtime.css:239](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L239) |
| "The values a theme is compared against are the values plugin pages start from" | [ThemeTokenResolver.swift:125-126](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L125-L126) | Does not hold: `runtime.css` redefines the accent, base colours, fonts and other defaults with different values | [CC-RUNTIME-09](#cc-runtime-09-two-default-style-layers-disagree-and-one-contradicts-its-own-header) |
| The default layer's version is 4 | [Architecture.md:282](../../../Docs/Architecture.md#L282) | Does not hold: the CSS header says 4, the resolver uses 5 | [graphite-default-variables.css:11](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L11), [ThemeTokenResolver.swift:37-38](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L37-L38) |
| Copies capped at 4 MB, changes gathered over 60 ms | [Architecture.md:349](../../../Docs/Architecture.md#L349) | Holds (the cap is 4 MiB of UTF-16 characters, not bytes) | [reading.js:17-22](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L17-L22) |
| Plugins' JavaScript never runs on the app's main thread | [Architecture.md:349](../../../Docs/Architecture.md#L349), OBJECTIVE.md | Holds by construction: the page runs in a `WKWebView` | [CommunityPluginHost.swift:381](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L381), [CommunityPluginHost.swift:401](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L401) |
| "Node: 84 runtime tests" | [Coverage.md:321](../../../Docs/Coverage.md#L321) | Stale: the snapshot has 85 `test(` calls in 12 files (grep `^\s*(test\|it\|describe)\(` over `tests/*.js`) | §8 |

## 2. File inventory

Physical and code lines are the reconnaissance figures; the responsibility is from reading each file.

| File | Physical | Code | Responsibility |
| --- | ---: | ---: | --- |
| [index.html](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/index.html) | 32 | 31 | Runtime page: viewport, style sheets, script load order |
| [dom-extensions.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-dom-extensions.js) | 372 | 346 | Obsidian's prototype and global helpers (`createEl`, `addClass`, `Array.prototype.contains`, `sleep`, `ajax`) |
| [foundation.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js) | 750 | 619 | Host channel, plugin attribution, unsupported reporting, `Events`, `Component`, utilities (paths, YAML, base64, search, HTML, `requestUrl`, `Platform`, `SecretStorage`) |
| [vault.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js) | 746 | 627 | File tree mirror, revision-checked `DataAdapter`, `Vault`, `FileManager`, Obsidian configuration defaults |
| [metadata.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js) | 708 | 626 | `NoteParser` (Markdown scanner with UTF-16 positions), `MetadataCache`, link resolution, `resolveSubpath` |
| [workspace.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js) | 1054 | 919 | `Editor`/`SnapshotEditor`, CodeMirror view stand-in, leaves and views, `Workspace`, Markdown rendering for plugins |
| [interface.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js) | 1225 | 1107 | Icons, tooltips, keyboard scopes, plugin panel state, notices, modals, setting controls, suggestion lists, menus |
| [settings.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-settings.js) | 278 | 246 | Obsidian 1.13 declarative settings, patched onto `SettingTab.prototype` |
| [bases.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js) | 427 | 370 | Bases value classes, `BasesView`, and the `basesView.open`/`update` handlers |
| [plugins.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js) | 1555 | 1324 | Module loader and `require`, command/ribbon/post-processor registries, `Plugin`, `App` and its stand-ins, typing, paste and drop, context menus, the host message dispatcher |
| [reading.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js) | 767 | 597 | Plugin blocks and views copied to native surfaces, event replay, style aggregation, live view, link interception |
| [host-connection.js](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-host-connection.js) | 59 | 43 | WebKit transport, clipboard and `window.open` through the host, uncaught error reporting |
| [runtime.css](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css) | 285 | 242 | Plugin panel look, Obsidian class styling, callouts, reading-area and live-view layout |
| [graphite-default-variables.css](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css) | 208 | 190 | Graphite's zero-specificity layer of Obsidian's CSS variables, shared with the theme resolver |
| **Total** | **8466** | **7287** | |

Tests covering the area: `Tests/CommunityPluginRuntimeTests/` has 12 test files with 85 tests, the harness [runtime-harness.js](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js) (167 lines) and the fake host [test-vault-host.js](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js) (267 lines). The tests pin:

- vault reads and writes, conflicts, `process` serialization, `types.json` batching, tree events and the byte-order mark (`vault.test.js`, 13 tests);
- editor batching, UTF-16 positions, transactions, read-only notes and refused changes (`editor-commands.test.js`, 7);
- metadata positions, link resolution and cloud skip (`metadata-cache.test.js`, 5);
- plugin load and unload (`plugin-loading.test.js`, 8), reading blocks (5), menus (4), file views (5), themes (4), typing (1), utilities (5), Obsidian conventions (10);
- 18 real plugins, each skipped when its build is absent ([real-plugins.test.js:191](../../../Tests/CommunityPluginRuntimeTests/tests/real-plugins.test.js#L191)).

Nothing tests `Scope`/`Keymap`: `grep "\['Mod'\]|scope\.register|handleKeyEvent|keymap"` over the tests finds no match.

## 3. Responsibility maps of the major types

No single class reaches 300 code lines; the largest is `NoteParser` at about 297 physical lines ([metadata.js:30-326](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L30-L326)). The aggregates that matter here are the global namespace, the file-level closures that act as modules (`plugins.js`, `reading.js`), and three classes with 15 or more stored fields (`App` 21, `Workspace` 20, `WorkspaceLeaf` 15). Field counts are by reading the constructors plus fields other files assign.

### 3.1 `GraphitePluginRuntime` (the global namespace)

**Stored state and functions by responsibility.** 50 members are assigned from 11 files (counted from `grep "runtime\.[a-zA-Z]+ = "`, duplicates removed).

| Responsibility | Members (defining file) |
| --- | --- |
| Host channel | `hostBridge`, `HostOperationError` (foundation) |
| Plugin attribution | `callingPluginIdentifier`, `pluginIdentifiersBySourceAddress`, `pluginIdentifierOfSource`, `pluginIdentifierInStack` (foundation); `pluginModuleFactories` (plugins) |
| Unsupported reporting | `reportUnsupportedFeature`, `unsupported`, `UnsupportedFeatureError` (foundation) |
| Version and platform | `compatibleApiVersion`, `compareVersions`, `configurePlatform` (foundation) |
| Plugin registries (mutable) | `markdownPostProcessors`, `codeBlockProcessors`, `settingTabsByPlugin`, `protocolHandlers`, `ribbon`, `editorSuggests` (plugins); `basesViews` (bases) |
| Change notifiers | `postProcessorsChanged`, `codeBlockLanguagesChanged`, `fileViewsChanged`, `editorListenersChanged`, `menuListenersChanged` (plugins); `basesViewsChanged` (bases) |
| Message dispatch | `messageHandlers`, `receive` (plugins); `basesMessageHandlers` (bases) |
| Cross-file helpers | `isHiddenPath`, `parentPath` (vault); `NoteParser` (metadata); `SnapshotEditor`, `convertInternalLinks`, `EmptyView`, `originalLeafSetViewState`, `pluginsTakeOverNotes` (workspace); `pluginSurface`, `tapNotice` (interface); `declarativeSettings` (settings); `runCodeBlockProcessor`, `runMarkdownPostProcessors`, `webAddressAtCursor`, `missingModuleExplanation` (plugins); `pluginStyles`, `bodyPresentation`, `placeNewLeaf`, `releaseAllCodeBlocks` (reading) |
| The application | `app` (plugins), `obsidianModule` (foundation) |

**Calls that cross responsibilities (coupling a split must preserve).**

- Earlier files call functions that only later files define. `Workspace.on/off/offref` call `runtime.menuListenersChanged` and `runtime.editorListenersChanged` ([workspace.js:729-744](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L729-L744)), defined in `plugins.js` ([plugins.js:1053](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1053), [plugins.js:1178](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1178)).
- The `Workspace` constructor reads `runtime.editorSuggests` ([workspace.js:725](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L725)).
- `createPluginLeaf` calls the optional `runtime.placeNewLeaf` from `reading.js` ([workspace.js:871](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L871), [reading.js:606](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L606)).
- `pluginSurface.drawSettingTab` calls the optional `runtime.declarativeSettings` ([interface.js:262](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L262)).
- `Vault.create` and `Vault.modify` reach the metadata cache through `runtime.app` ([vault.js:552](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L552), [vault.js:570](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L570)).
- Handlers are merged across files. `plugins.js` copies `bases.js`'s handlers in ([plugins.js:1536-1538](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1536-L1538)), and `reading.js` adds nine more by mutating `runtime.messageHandlers` ([reading.js:661](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L661)).

**Lifecycle and ordering rules.**

- The script order in `index.html` is a correctness rule ([index.html:11](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/index.html#L11)).
- `reading.js` must load after `plugins.js` (it writes into `runtime.messageHandlers`). `bases.js` must load before `plugins.js` (its handlers are merged at load).
- `runtime.app` exists only after `runtime.start` ([plugins.js:1245-1248](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1245-L1248)). Handlers such as `plugin.load` dereference it unguarded ([plugins.js:1276-1278](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1276-L1278)); `receive` turns the resulting `TypeError` into a failure answer.
- All module-level state lives as long as the page. The host builds a new web view and loads the page again for every start ([CommunityPluginHost.swift:371-401](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L371-L401)), so a vault switch resets every registry.

**Verdict.** One application-wide aggregate that every file reads and writes. **Split:** each file exports one named object it owns, and later files register through functions, never by assigning into another file's object.

| New object | Members |
| --- | --- |
| `HostChannel` | `send`, `notify`, `HostOperationError`, generated operation names |
| `PluginAttribution` | the four attribution members and `pluginModuleFactories` |
| `UnsupportedFeatures` | `report`, `fail`, `UnsupportedFeatureError` |
| `PluginRegistries` | the seven registries, each with its own coalesced notifier |
| `HostMessageRouter` | `register(operationName, handler)`, `receive` |
| `RuntimeSession` | `app` and `compatibleApiVersion` |

### 3.2 `plugins.js` (module) and `App`

**Responsibilities in the closure.** 1324 code lines; line ranges by reading.

| Responsibility | Lines |
| --- | --- |
| Node/Electron module names and explanations | [16-45](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L16-L45) |
| ES5-callable class shim (`callableClass`, `pluginFacingObsidianModule`) | [47-85](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L47-L85) |
| Evaluating `main.js` (eval or blob script, stack probe, 20 s timeout) | [87-143](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L87-L143) |
| Desktop module stand-ins and `require` | [145-184](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L145-L184) |
| `CommandRegistry` and failure reporting | [188-259](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L188-L259) |
| `RibbonRegistry` | [263-294](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L263-L294) |
| Post-processor and code block registries, their notifiers and runners | [298-370](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L298-L370) |
| `Plugin` (data, commands, ribbon, tabs, views, extensions, processors, suggests, protocol handlers, Bases views) | [374-541](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L374-L541) |
| CodeMirror 5 mode registry stand-in | [548-583](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L548-L583) |
| `PluginManager` (load, unload, styles) | [590-670](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L590-L670) |
| `InternalPluginRegistry` with a canvas stand-in | [674-711](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L674-L711) |
| `MetadataTypeManager` (`types.json`) | [715-785](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L715-L785) |
| Embed and view registries | [789-843](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L789-L843) |
| `App` and its stand-ins (fold, hotkey, setting, status bar, local storage, theme) | [845-926](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L845-L926) |
| `CustomCss` (theme and snippets in the page) | [931-996](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L931-L996) |
| File-view notifier with timed re-checks | [998-1023](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L998-L1023) |
| Vim adapter stand-in | [1030-1041](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1030-L1041) |
| Typing: listener notifier, paste/drop transfer, suggestions | [1046-1171](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1046-L1171) |
| Context menus | [1175-1231](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1175-L1231) |
| Host-to-runtime dispatcher (28 handlers) and `receive` | [1235-1550](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1235-L1550) |

**`App` stored state** (21 fields, [plugins.js:846-902](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L846-L902)):

- `keymap`, `scope`, `vault`, `workspace`, `metadataCache`, `fileManager`, `commands`, `plugins`, `internalPlugins`, `secretStorage`, `metadataTypeManager`;
- `embedRegistry`, `viewRegistry`, `statusBar`, `foldManager`, `hotkeyManager`, `customCss`, `lastEvent`, `isMobile`, `appId`, `setting`.

The field set is Obsidian's public and undocumented `app` surface that plugins read, so the count is a recorded reason, not a defect. The constructor itself (57 lines) builds four stand-in objects inline (`foldManager`, `hotkeyManager`, `setting`, `statusBar`).

**Crossing calls.**

- `Plugin.addSettingTab` closes the panel through `runtime.pluginSurface.handleClosedByPerson` when its tab unloads ([plugins.js:440-445](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L440-L445)).
- `PluginManager.loadPlugin` calls `runtime.fileViewsChanged` and starts timed re-checks ([plugins.js:626-627](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L626-L627)).
- `runtime.stop` calls `releaseAllCodeBlocks` from `reading.js` ([plugins.js:1271](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1271)).

**Ordering rules.** `runtime.start` runs these steps in order ([plugins.js:1245-1266](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1245-L1266)), and `metadataCache.observeVault` must follow `loadFileTree`, so that the initial listing raises no `create` events:

1. create `App`;
2. publish it as `runtime.app` and `window.app`;
3. set the vault fields;
4. configure core plugins and secrets;
5. configure the platform and apply the theme;
6. load the file tree (awaited);
7. load the property types (awaited);
8. `observeVault`;
9. `startInitialRead` (not awaited).

The host sends `plugins.layoutReady` only after every plugin loads ([CommunityPluginHost.swift:411-416](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L411-L416)).

**Verdict and split.** One file per responsibility row:

- `plugin-module-loader.js`: shim, evaluation, stand-ins, `require`;
- `plugin-registries.js`: commands, ribbon, processors, suggests, protocol handlers, setting tabs;
- `plugin.js`: `Plugin`;
- `plugin-manager.js`;
- `app.js`: `App` with the stand-ins as named classes `FoldManagerStandIn`, `HotkeyManagerStandIn`, `SettingWindowStandIn`;
- `property-types.js`: `MetadataTypeManager`;
- `custom-css.js`;
- `editor-typing.js`: suggestions, paste, drop;
- `context-menus.js`;
- `host-messages-application.js`: the handlers, each registered through `HostMessageRouter`.

### 3.3 `Workspace`, `WorkspaceLeaf` and `SnapshotEditor`

**`Workspace` state** (20 fields: 19 in [workspace.js:704-726](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L704-L726) plus `eventReferencesByName`) and 43 members, by responsibility:

| Responsibility | State | Functions |
| --- | --- | --- |
| Obsidian layout objects (inert) | `containerEl`, `rootSplit`, `leftSplit`, `rightSplit`, `leftRibbon`, `rightRibbon`, `requestSaveLayout` | `getLayout`, `changeLayout`, `updateOptions`, `iterateCodeMirrors`, popout stubs |
| Mirror of Graphite's focus | `markdownLeaf`, `activeLeaf`, `activeEditor`, `activeFilePath`, `lastOpenFiles` | `setActiveDocument`, `updateEditorSnapshot`, `getActiveFile`, `getActiveViewOfType`, `getActiveFileView` |
| Plugin leaf registry | `pluginLeaves`, `viewCreatorsByType`, `revealedLeaf` | `getLeaf`, `createPluginLeaf`, `getLeavesOfType`, `getLeafById`, `detachLeavesOfType`, `iterateAllLeaves`, `ensureSideLeaf`, `revealLeaf`, `setActiveLeaf` |
| Host notification | none | `notifyLeavesChanged`, the `on/off/offref` overrides that report listener counts |
| Layout readiness | `layoutReady`, `layoutReadyCallbacks` | `markLayoutReady`, `onLayoutReady` |
| Links | none | `openLinkText`, `handleLinkContextMenu` |

**`WorkspaceLeaf` state** (15 fields):

- 10 in its constructor ([workspace.js:573-588](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L573-L588)): `app`, `kind`, `id`, `view`, `pinned`, `isDeferred`, `waitingViewState`, `containerEl`, `tabHeaderEl` and its two children;
- `hasBeenShown`, set by its own `showIfNew`, by `bases.js` ([bases.js:366](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L366)) and by `plugins.js` ([plugins.js:1303](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1303), [plugins.js:1331](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1331));
- `isProbe`, set by `plugins.js` ([plugins.js:1304](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1304));
- `waitingPlace`, set by `reading.js` ([reading.js:612](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L612));
- `eventReferencesByName`.

**`SnapshotEditor` state** (10 fields, [workspace.js:163-174](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L163-L174), [workspace.js:160](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L160), [workspace.js:368](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L368)):

- `path`, `snapshotIdentifier`, `text`, `isReadOnly`, `lineStarts`, `selections`, `mainSelectionPosition`;
- `hasUnsentChanges`, `pendingFlush`, `changingPluginIdentifier`.

**Crossing calls.**

- `setActiveDocument` creates file-tree entries through `vault.addAbstractFile` ([workspace.js:756-758](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L756-L758)).
- It reuses one `MarkdownView` and one `SnapshotEditor` for every note ([workspace.js:762-768](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L762-L768), [workspace.js:782-788](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L782-L788)), which is the root of BUG-RUNTIME-01.
- `WorkspaceLeaf.setViewState` sends `workspace.openFile` for Markdown, unless the leaf is a probe ([workspace.js:594-604](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L594-L604)).

**Ordering rules.**

- A view state whose type is not registered waits on the leaf (`waitingViewState`). `Plugin.registerView` replays it ([plugins.js:448-456](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L448-L456)).
- `isProbe` must be reset after the probe ([plugins.js:1310](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1310)).
- `hasBeenShown` must be set before `setViewState` when the host shows the leaf itself ([plugins.js:1303](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1303)).
- `pluginsTakeOverNotes` compares the current `setViewState` with the original captured at load ([workspace.js:693-694](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L693-L694)), so it must be captured before any plugin loads.

**Verdict and split.** Keep `Workspace`'s Obsidian-facing surface, which is mandated. Move the Graphite-only parts out:

- `FocusMirror`: `setActiveDocument`, `updateEditorSnapshot`, and one `SnapshotEditor` per note path held in a map;
- `LeafHostState`: a value per leaf (`placement`, `presentation`: `hidden | waitingForHost | shownByHost | probe`) owned by one module, replacing `hasBeenShown`, `isProbe` and `waitingPlace`;
- `LeafChangeReporter`: `notifyLeavesChanged`.

### 3.4 `DataAdapter` and `Vault`

**`DataAdapter`**: 4 fields (`vault`, `revisionsByPath`, `processCallsByPath`, and `writesByPath` created lazily at [vault.js:202](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L202)) and 28 methods.

| Responsibility | Methods |
| --- | --- |
| Reads | `exists`, `stat`, `list`, `read`, `readBinary`, `absentObsidianSettingsFileText` |
| Revision bookkeeping | `writeExpectation`, `forgetRemovedPath`, `moveRevisions` |
| Writes | `writeData`, `writeInTurn`, `write`, `writeBinary`, `append`, `appendBinary`, `process`, `processNow`, `applyTimes` |
| Folder and file operations | `mkdir`, `trashSystem`, `trashLocal`, `rmdir`, `remove`, `rename`, `copy` |
| Addresses | `getName`, `getFullPath`, `getResourcePath` |

**`Vault`**: 7 fields (`vaultName`, `configDir`, `configuration`, `adapter`, `abstractFilesByPath`, `root`, plus `appearanceConfiguration`, which `plugins.js` assigns at [plugins.js:1259](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1259) and [plugins.js:1357](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1357)). Its responsibilities are tree reconciliation (`addHostEntries` through `reconcileChangedPaths`), Obsidian's queries, operations that partly bypass the adapter, and configuration (`config`, `getConfig`, `setConfig`).

**Crossing calls.**

- `writeData` updates the tree through `vault.reconcileWrittenPath` ([vault.js:193-194](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L193-L194)), which raises the `modify` event the metadata cache reads.
- `Vault.delete` and `Vault.trash` send `vault.remove` themselves and then call the adapter's bookkeeping ([vault.js:584-591](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L584-L591)).

**Ordering rules.**

- A write's expectation is computed when its turn comes, not when it is queued: the closure calls `writeExpectation` at run time ([vault.js:214](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L214)).
- The plugin identifier must be read before the first `await` ([vault.js:178-181](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L178-L181)).
- A revision recorded by a read survives an external change notice, so a later write still conflicts ([vault.js:468-469](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L468-L469)).

**Verdict and split.** `DataAdapter` is coherent apart from its two queues, which `PathWriteQueue` would replace. One `PathWriteQueue` (per path, used by `write`, `writeBinary`, `append`, `appendBinary` and `process`) holds the serialization. `Vault` keeps Obsidian's API and delegates every removal to the adapter. Configuration moves to `VaultConfiguration`, which owns the merged view used by both `config` and `getConfig`.

### 3.5 `reading.js` (module)

**Module-level mutable state** (7 variables): `drawnBlocks`, `lastSentStyles`, `isStyleNotificationScheduled`, `lastViewSizes`, `isWorkspaceResizeScheduled`, `liveLeaf`, `liveContainer`.

**Responsibilities.**

1. Marking listeners by patching `EventTarget.prototype.addEventListener` for every object on the page ([reading.js:51-67](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L51-L67)).
2. Replaying events from copies: context menu, hover, gesture, drag, tap, key, input ([reading.js:69-201](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L69-L201), [reading.js:515-552](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L515-L552)).
3. Copying HTML with live state ([reading.js:207-294](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L207-L294)).
4. Gathering and observing page styles ([reading.js:296-371](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L296-L371)).
5. The block lifecycle: draw, section, release ([reading.js:375-513](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L375-L513)).
6. Leaf placement, view attachment and the live view ([reading.js:556-659](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L556-L659)).
7. Nine host handlers ([reading.js:661-731](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L661-L731)).
8. Link interception for the whole page ([reading.js:744-765](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L744-L765)).

**Ordering rules.**

- `release` must run before a block identifier is reused (`draw`, `drawSection` and `attachView` each call it first).
- `showLive` must call `hideLive` first and must release copies of the same leaf ([reading.js:627-630](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L627-L630)).
- `followReplacement` mutates `entry.element` and must run before every copy ([reading.js:252-266](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L252-L266)).
- The listener patch must be installed before any plugin adds a listener, which holds because the file loads before any plugin.

**Verdict and split.** `ListenerMarking` (the patch, isolated and documented as the one global patch), `CopyEventReplay`, `BlockCopy` (copy, live state, change watch), `PageStyleReporter`, `ReadingBlocks` (draw, section, release, keyed by block identifier), `PluginViewPlacement` (waiting places, sizes, live view), `LinkInterception`.

### 3.6 `MetadataCache` and `NoteParser`

**`MetadataCache`**: 10 fields ([metadata.js:360-372](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L360-L372)).

| Responsibility | Members |
| --- | --- |
| Obsidian queries | `getFileCache`, `getCache`, `getCachedFiles`, `fileToLinktext`, `getFirstLinkpathDest`, `getLinkpathDest`, `getTags`, `getBacklinksForFile`, `getAllPropertyInfos`, `getFrontmatterPropertyValuesForKey` |
| Link resolution | `resolveLinkpath`, `findFileIgnoringCase`, the name index, `resolveLinksOf`, `resolveAllLinks`, `scheduleLinkResolution` |
| Read queue | `startInitialRead`, `enqueueRead`, `pumpReadQueue`, `readNote`, `indexWrittenText` |
| Vault observation | `observeVault` |

`NoteParser` is one 187-line `parseBody` plus inline scanning ([metadata.js:88-274](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L88-L274), [metadata.js:286-325](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L286-L325)).

**Ordering rules.**

- `rebuildNameIndex` must run before the first read ([metadata.js:536](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L536)).
- Link resolution is suppressed until `isInitialReadComplete` ([metadata.js:528](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L528)).
- A read is dropped when the file object was replaced meanwhile ([metadata.js:575](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L575), [metadata.js:578](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L578)), but not when a newer read of the same file finished first (BUG-RUNTIME-06).

**Verdict and split.**

- `NoteParser.parseBody` becomes a block classifier that returns one block kind per line, plus separate section, list and block-identifier builders.
- `LinkResolver` (name index and resolution) leaves the cache.
- The read queue becomes `NoteReadQueue`, which keeps the latest request per path.

### 3.7 `pluginSurface` (plugin panel state)

**State** ([interface.js:186-283](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L186-L283)): four interacting fields, `openModals`, `shownSettingTab`, `settingPages` and `isPresented`.

**How presentation is derived.** Whether the panel is presented is computed by hand at five sites, and `isPresented` is reset in two places:

- `present` ([interface.js:229-234](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L229-L234));
- `dismissIfEmpty` ([interface.js:235-241](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L235-L241));
- `showSettingTab`;
- `modalOpened`/`modalClosed`;
- `handleClosedByPerson` ([interface.js:277-282](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L277-L282)).

**Verdict.** A flow with more than two states kept as loose fields. A `PanelContent` value (`empty | settingTab(tab, pages) | modals(stack, under)`) with intent methods would make presentation a projection.

## 4. Findings by principle

### S

#### SRP-RUNTIME-01 `plugins.js` is one 1324-code-line closure with about 18 responsibilities
- **Severity:** Medium
- **Evidence:**
  - The closure spans [plugins.js:4-1554](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L4-L1554) and holds the 20 responsibility rows of §3.2.
  - It contains the module loader ([plugins.js:109-143](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L109-L143)), `App` ([plugins.js:845-926](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L845-L926)), typing suggestions ([plugins.js:1125-1171](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1125-L1171)) and 28 host handlers ([plugins.js:1244-1521](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1244-L1521)).
  - It is the most-changed runtime file: 16 of 242 commits (reconnaissance).
- **Why it matters:** every change to typing, menus, loading or theming edits the same closure. Its private helpers (`checkFileViewsOverTheNextSeconds`, `reportCommandFailure`, `shownSuggestion`) are reachable by every handler, so a typing change can break plugin loading with no module boundary to stop it.
- **Fix direction:** split along the §3.2 rows into one file per responsibility. Handlers register through a router, and `index.html` lists the new files.

#### SRP-RUNTIME-02 The global `GraphitePluginRuntime` namespace is a service locator and a shared mutable registry
- **Severity:** High
- **Evidence:**
  - 50 members are assigned from 11 files (§3.1, counted with `grep "runtime\.[a-zA-Z]+ = "`).
  - `runtime.app` is read 61 times in 6 files (`grep "runtime\.app\b"`).
  - Earlier files call functions only later files define ([workspace.js:731-732](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L731-L732) uses [plugins.js:1053](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1053)).
  - Registries are reassigned wholesale from two files ([plugins.js:481](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L481), [workspace.js:1036](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L1036)).
- **Why it matters:**
  - No file can be loaded or tested alone. The harness always evaluates all eleven scripts in order ([runtime-harness.js:104-106](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L104-L106)).
  - Reordering `index.html` or renaming a member fails only at run time, when the message that uses it arrives.
  - Reassigning `runtime.markdownPostProcessors` replaces the array other files captured.
- **Fix direction:** each file owns one exported object, and cross-file needs are passed in at construction or registered through functions (§3.1 split). Plugins are given the `App`; runtime code is never handed the namespace as a whole.

#### SRP-RUNTIME-03 `reading.js` mixes a global prototype patch, event replay, DOM copying, style reporting, view placement and link interception
- **Severity:** Medium
- **Evidence:**
  - The eight responsibilities of §3.5, with 7 module-level mutable variables ([reading.js:28](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L28), [reading.js:340-341](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L340-L341), [reading.js:579](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L579), [reading.js:593](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L593), [reading.js:620-621](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L620-L621)).
  - The page-wide click handler for links ([reading.js:765](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L765)) and the leaf placement hook ([reading.js:606-613](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L606-L613)) concern every plugin view, not reading blocks.
- **Why it matters:** the live view, which carries Apple Pencil input to Excalidraw, shares a file and its state with code-block copying. A change to copy timing or event replay risks the Pencil path, OBJECTIVE.md's top priority.
- **Fix direction:** split into the seven objects named in §3.5, with `PluginViewPlacement` owning `liveLeaf`, `liveContainer` and `lastViewSizes`.

#### SRP-RUNTIME-04 `Workspace` and `WorkspaceLeaf` carry Graphite's host protocol as loose fields alongside Obsidian's API
- **Severity:** Medium
- **Evidence:**
  - Graphite-focus mirroring sits in the API class ([workspace.js:751-789](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L751-L789)), as does host reporting ([workspace.js:807-828](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L807-L828)).
  - Leaf presentation lives in three loose fields written from four files: `hasBeenShown` ([workspace.js:649-650](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L649-L650), [bases.js:366](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L366), [plugins.js:1303](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1303), [plugins.js:1331](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1331)), `isProbe` ([plugins.js:1304](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1304), [plugins.js:1310](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1310)) and `waitingPlace` ([reading.js:566](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L566), [reading.js:612](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L612), [reading.js:631](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L631), [workspace.js:684](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L684)).
- **Why it matters:** a leaf's presentation depends on the caller remembering to set `hasBeenShown` before `setViewState` and to clear `isProbe` afterwards. One missed write makes a leaf open a second tab, or never show. BUG-RUNTIME-03 is one such case.
- **Fix direction:** one `LeafHostState` value per leaf, changed only through intent functions (`markShownByHost`, `beginProbe`, `endProbe`, `placeWaiting`). `Workspace` keeps only Obsidian's members.

#### SRP-RUNTIME-05 The adapter has two per-path serialization queues and some writes use neither
- **Severity:** Medium
- **Evidence:**
  - `write` and `writeBinary` queue in `writesByPath` ([vault.js:201-223](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L201-L223)).
  - `process` and `append` queue in `processCallsByPath` ([vault.js:228-261](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L228-L261)).
  - The two `appendBinary` implementations use neither ([vault.js:231-240](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L231-L240), [vault.js:574-582](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L574-L582)).
  - `Vault.delete` and `Vault.trash` send their own `vault.remove` instead of using the adapter's removal methods ([vault.js:584-591](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L584-L591)).
- **Why it matters:** a `saveData` that runs alongside a `process` on the same file is not ordered with it. Correctness then rests on the host's conflict refusal and the retry loop, and a plugin sees a conflict error Obsidian would not raise. Removal rules live in two classes.
- **Fix direction:** one `PathWriteQueue` used by every write and append, and every `Vault` removal delegated to one adapter method that takes the removal method as an enum value.

#### SRP-RUNTIME-06 Plugin panel presentation is derived by hand from four fields
- **Severity:** Low
- **Evidence:** §3.7. `isPresented` is written in [interface.js:230](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L230), [interface.js:238](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L238) and [interface.js:280](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L280). The page under the top setting page is computed twice ([interface.js:198](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L198), [interface.js:217](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L217)).
- **Why it matters:** `handleClosedByPerson` closes modals first, which runs `dismissIfEmpty` and sends `surface.dismiss` for a panel the person already closed. The ordering of these side effects is implicit.
- **Fix direction:** a `PanelContent` enum with intent methods; whether the panel is presented is a projection, and `surface.present`/`surface.dismiss` are sent only on a change of that projection.

### O

#### OCP-RUNTIME-01 83 message names and their payloads are literals kept in step by hand in three places
- **Severity:** High
- **Evidence:**
  - 44 distinct runtime-to-host operation names over 70 call sites: 33 `send`, 37 `notify` (`grep "(send|notify)\('([a-zA-Z]+\.[a-zA-Z]+)'"`). Examples: [vault.js:184](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L184), [workspace.js:816](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L816), [reading.js:293](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L293).
  - 39 host-to-runtime handler names: 28 in [plugins.js:1244-1521](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1244-L1521), 2 in [bases.js:361-410](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L361-L410), 9 in [reading.js:661-731](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L661-L731).
  - The same names are typed again in Swift ([CommunityPluginHost.swift:871-913](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L871-L913), [CommunityPluginHost.swift:938-1000](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L938-L1000)) and in the fake host ([test-vault-host.js:75-129](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L75-L129)).
  - In Swift, any operation the switch does not name falls to `default` and is treated as a notification ([CommunityPluginHost.swift:910-912](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L910-L912)).
- **Why it matters:** a renamed operation or payload field on one side is silent on the other: a request answers `{}`, a notification is ignored. The fake host keeps the tests green while production breaks. LSP-RUNTIME-01 and LSP-RUNTIME-02 show the copies have already drifted.
- **Fix direction:** one typed declaration of operations and payload fields (a JSON schema in the resources folder) from which the Swift enum, the runtime's constant table and the fake host's switch are generated. Add a contract test that every declared operation has a handler on its receiving side.

#### OCP-RUNTIME-02 Adding a listener-gated plugin event touches four places
- **Severity:** Medium
- **Evidence:**
  - Two hard-coded sets ([workspace.js:26](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L26), [workspace.js:28](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L28)) and three overridden methods that consult them ([workspace.js:729-744](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L729-L744)).
  - Two notifiers whose payloads name each event ([plugins.js:1059-1064](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1059-L1064), [plugins.js:1185-1189](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1185-L1189)).
  - Matching Swift fields ([CommunityPluginHost.swift:964-968](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L964-L968), [CommunityPluginHost.swift:980-982](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L980-L982)).
- **Why it matters:** adding `files-menu`-style events or a new editor event means editing the set, the payload builder, the Swift parser and the Swift state. Forgetting the set leaves the host believing no plugin listens.
- **Fix direction:** one table `listenerGatedEvents: [{ eventName, reportField }]` drives the overrides and one notifier, and the payload becomes a map from event name to listener count.

#### OCP-RUNTIME-03 Feature files join the runtime by mutating other files' objects in script order
- **Severity:** Medium
- **Evidence:**
  - `bases.js` publishes `runtime.basesMessageHandlers` for `plugins.js` to copy at load ([bases.js:358](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L358), [plugins.js:1537](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1537)).
  - `reading.js` assigns into `runtime.messageHandlers` ([reading.js:661](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L661)).
  - `settings.js` replaces four methods on `SettingTab.prototype` and wraps a fifth ([settings.js:247-274](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-settings.js#L247-L274)).
  - The order is enforced only by a comment ([index.html:11](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/index.html#L11)).
- **Why it matters:** a new feature file must know which global to mutate and where to sit in `index.html`. Placing `bases.js` after `plugins.js` silently drops two handlers (the copy happens once, at load).
- **Fix direction:** a `HostMessageRouter.register` call per handler from its own file, valid whenever it runs before `runtime.start`. Declarative settings become a collaborator the panel asks for, not a prototype patch.

### L

#### LSP-RUNTIME-01 The Node test host accepts editor changes that production refuses
- **Severity:** Medium
- **Evidence:**
  - The fake accepts any change whose identifier matches the session's single identifier, and never compares text ([test-vault-host.js:223-229](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L223-L229)).
  - Production refuses a change when the note's text differs from the snapshot's, answers with a fresh `snapshot`, and refuses notes in reading view ([CommunityPluginHost.swift:768-775](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L768-L775)).
  - The one test of a refusal fakes it by wrapping both the host and the transport by hand ([editor-commands.test.js:167-185](../../../Tests/CommunityPluginRuntimeTests/tests/editor-commands.test.js#L167-L185)).
- **Why it matters:** RULES.md says a test adapter must not make an operation appear safer than production. Every other editor test passes even if the runtime sends an edit based on stale text; BUG-RUNTIME-01 passes the fake for the same reason.
- **Fix direction:** the fake keeps snapshots by identifier with their text, compares text, returns `snapshot` on refusal and refuses `isReadOnly`, exactly as production does. A shared table of cases then runs against both.

#### LSP-RUNTIME-02 Tests pin a `vault.changes` shape that production never sends
- **Severity:** Medium
- **Evidence:**
  - The test sends `moves` and `stat` values ([vault.test.js:195-197](../../../Tests/CommunityPluginRuntimeTests/tests/vault.test.js#L195-L197)).
  - Production sends only `{ path, isReloadNeeded: true }` per path and no `moves` ([CommunityPluginHost.swift:807-810](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L807-L810)).
  - The runtime's `moves` branch ([plugins.js:1368](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1368)) and its `stat` fast path ([vault.js:474-475](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L474-L475)) are reached only by tests.
- **Why it matters:** in production a rename made outside the runtime reaches plugins as `delete` plus `create`, never as Obsidian's `rename`. Plugins that key data by path (Recent Files, bookmarks) lose their entries. The test that says renames arrive as `rename` pins a path the app never takes.
- **Fix direction:** decide the production contract. Either the host reports moves, or the runtime documents delete-plus-create. Then the test uses exactly the production payload.

#### LSP-RUNTIME-03 `Vault.config` and `Vault.getConfig` answer differently for the same keys
- **Severity:** Low
- **Evidence:** `config` overrides `cssTheme`, `theme` (from the page's body class) and `baseFontSize` before merging ([vault.js:608-610](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L608-L610)). `getConfig` returns stored values, then Obsidian's defaults, where `theme` is `'system'` ([vault.js:613-618](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L613-L618), [vault.js:82](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L82)).
- **Why it matters:** two readers of one setting disagree. BUG-RUNTIME-07 is the visible consequence.
- **Fix direction:** one `VaultConfiguration.value(key)` used by both members.

#### LSP-RUNTIME-04 Two functions decide a leaf's placement and disagree for split leaves
- **Severity:** Low
- **Evidence:** `placementOf` returns `'split'` for split leaves ([workspace.js:21-24](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L21-L24)); `placementOfLeaf` returns `'tab'` for them ([reading.js:580](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L580)).
- **Why it matters:** a split view is reported to the host as `split` but sized and remembered as a tab. The next tab opens at the split's last size.
- **Fix direction:** one placement function, exported once, with a size key per placement.

#### LSP-RUNTIME-05 `ObjectValue.entries` is an object or an array of pairs depending on who built it
- **Severity:** Low
- **Evidence:** the default is `{}` ([bases.js:94](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L94)), but `wrapValue` and `receivedValue` pass arrays of `[key, Value]` pairs ([bases.js:162](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L162), [bases.js:186](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L186)), and `toString` serializes whichever it holds ([bases.js:96](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L96)).
- **Why it matters:** a plugin view reading `value.entries.status` gets `undefined` for frontmatter objects, and the shown text is `[["status",{"value":"open"}]]` rather than an object.
- **Fix direction:** one constructor shape, an object of `Value`s, built by both paths.

#### LSP-RUNTIME-06 Stand-ins that report success for work they did not do
- **Severity:** Low
- **Evidence:**
  - `Editor.hasFocus()` always answers `true` ([workspace.js:41](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L41)).
  - `views.saveFiles` answers `savedCount` as the number of views it attempted, including saves that failed or timed out after 3 s ([reading.js:664-669](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L664-L669)).
  - `Plugin.registerHoverLinkSource` is a silent no-op ([plugins.js:519](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L519)), while `Workspace.registerHoverLinkSource` reports the feature unsupported ([workspace.js:933](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L933)).
- **Why it matters:** RULES.md forbids placeholder success paths. A host that someday trusts `savedCount` before closing would discard unsaved plugin work.
- **Fix direction:** return `{ savedCount, failedPaths }` from settled results, and route both hover registrations to the same report.

### I

#### ISP-RUNTIME-01 Every message crosses the boundary as an untyped dictionary built inline
- **Severity:** Medium
- **Evidence:**
  - Payloads are object literals at each call site, for example the 8-field view description ([workspace.js:816-827](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L816-L827)), parsed in Swift field by field with `as?` casts and silent defaults ([CommunityPluginHost.swift:949-956](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L949-L956)).
  - Answers are read by property name with defaults ([vault.js:139](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L139), [interface.js:1177](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L1177)).
- **Why it matters:** a misspelled field becomes a default on the other side (`placement` falls back to `.tab`, `isLive` to `false`) with no error and no test that spans both sides.
- **Fix direction:** generated payload types from the OCP-RUNTIME-01 schema, with one validation at each receiving edge that reports an unknown or missing field.

#### ISP-RUNTIME-02 Nine fields are written onto objects from files that do not own them
- **Severity:** Medium
- **Evidence:**
  - `vault.configuration` and `vault.appearanceConfiguration` ([plugins.js:1252](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1252), [plugins.js:1259](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1259), [plugins.js:1345](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1345), [plugins.js:1357](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1357)).
  - `leaf.hasBeenShown`, `leaf.isProbe` and `leaf.waitingPlace` (SRP-RUNTIME-04).
  - `hostView.viewName`, `groupBy`, `basesView` and `controller` ([bases.js:368](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L368), [bases.js:378](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L378), [bases.js:390-391](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L390-L391)).
  - `workspace.lastOpenFiles` ([plugins.js:1256](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1256), [plugins.js:1363](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1363)).
- **Why it matters:** the owning class cannot enforce its own invariants. `PluginBasesHostView` declares none of the four fields, and `Vault` initialises `appearanceConfiguration` nowhere, so readers guard with `|| {}` ([vault.js:609](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L609), [vault.js:615](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L615), [vault.js:624](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L624)).
- **Fix direction:** each class takes these values through one method (`vault.adoptConfiguration(applicationSettings, appearanceSettings)`, `hostView.attach(controller, view, groupBy)`) and declares the fields in its constructor.

### D

#### DIP-RUNTIME-01 Domain classes reach the host channel and the application through globals
- **Severity:** Medium
- **Evidence:**
  - 70 `hostBridge.send`/`notify` call sites in `Vault`, `DataAdapter`, `MetadataCache`, `Workspace`, `WorkspaceLeaf`, `SnapshotEditor`, `Notice`, `Menu` and others (§8).
  - `Vault` calls up into `MetadataCache` through `runtime.app` ([vault.js:552](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L552), [vault.js:570](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L570)).
  - `View` and `Modal` fall back to `runtime.app` ([workspace.js:453](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L453), [interface.js:349](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L349)).
- **Why it matters:** the only substitution point is the transport, so testing `MetadataCache` alone means faking the whole host protocol. The vault-to-metadata call inverts the layering (the cache observes the vault, and the vault also calls the cache).
- **Fix direction:** pass a narrow `HostChannel` into the constructors of the classes that talk to the host. Replace the upward call with the cache listening to a `written` event carrying the text, which `Vault.create`/`modify` raise.

#### DIP-RUNTIME-02 Clock, randomness and storage are called inline
- **Severity:** Low
- **Evidence:** `Date.now()` names leaves ([workspace.js:18](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L18)); `Math.random()` names post-processor documents ([plugins.js:335](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L335)); `moment()` renders samples ([interface.js:504](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L504)); `localStorage` is called directly ([plugins.js:903-918](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L903-L918)).
- **Why it matters:** leaf identifiers are persisted by the host with the tab layout. Their prefix depends on the wall clock at start, which no test can pin.
- **Fix direction:** one `RuntimeClock` and one identifier source passed to `Workspace`. The prefix comes from the host's `runtime.start` message.

#### DIP-RUNTIME-03 One platform prototype is patched for the whole page
- **Severity:** Medium
- **Evidence:** `EventTarget.prototype.addEventListener` is replaced for every object in the page, including vendored CodeMirror and every plugin. The replacement writes a `data-graphite-listens` attribute on each element that gains a forwarded listener ([reading.js:58-67](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L58-L67)).
- **Why it matters:**
  - Each such attribute write is a DOM mutation that the block observers count as a change ([reading.js:427-428](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L427-L428)).
  - Plugins that compare attributes or serialize elements see Graphite's attribute.
  - The patch is invisible from the call sites that rely on it.
  - The DOM additions in `dom-extensions.js` are Obsidian's documented API; this patch is not.
- **Fix direction:** keep the patch in one file named for it, apply it only to elements inside the reading area or a plugin leaf, and record why no event-delegation alternative works.

### Clean code

#### CC-RUNTIME-01 Eleven functions run over 40 lines; the longest is 187
- **Severity:** Medium
- **Evidence:** physical lines from the first to the last line of each function, by reading.

| Function | Lines | Location |
| --- | ---: | --- |
| `NoteParser.parseBody` | 187 | [metadata.js:88-274](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L88-L274) |
| `renderControl` | 73 | [settings.js:123-195](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-settings.js#L123-L195) |
| `App` constructor | 57 | [plugins.js:846-902](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L846-L902) |
| `SnapshotEditor.exec` | 50 | [workspace.js:306-355](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L306-L355) |
| `findSuggestions` | 47 | [plugins.js:1125-1171](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1125-L1171) |
| `gesture` | 46 | [reading.js:156-201](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L156-L201) |
| `PluginManager.loadPlugin` | 45 | [plugins.js:601-645](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L601-L645) |
| `htmlToMarkdown` | 43 | [foundation.js:517-559](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L517-L559) |
| `copyLiveState` | 41 | [reading.js:207-247](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L207-L247) |
| `'basesView.open'` | 41 | [bases.js:361-401](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L361-L401) |
| `NoteParser.parseInline` | 40 | [metadata.js:286-325](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L286-L325) |

- **Why it matters:** `parseBody` keeps six mutable flags (`currentSection`, `fence`, `isInMathBlock`, `isInComment`, `listParents`, `listFirstLine`) across 13 branches. Each new Markdown construct changes branch order, and metadata positions are what plugins such as Tasks and Dataview edit by.
- **Fix direction:** `parseBody` becomes a line classifier returning a block kind, plus small builders per kind. `renderControl` becomes a table from control type to a builder.

#### CC-RUNTIME-02 The same code is copied in eight patterns
- **Severity:** Medium
- **Evidence:**
  - `error && error.message ? error.message : String(error)`: 15 copies (grep), for example [plugins.js:258](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L258) and [reading.js:457](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L457).
  - The "flag, microtask, notify" coalescer: 7 copies ([plugins.js:238-253](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L238-L253), [plugins.js:307-315](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L307-L315), [plugins.js:317-326](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L317-L326), [plugins.js:1004-1020](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1004-L1020), [plugins.js:1053-1066](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1053-L1066), [plugins.js:1178-1191](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1178-L1191), [bases.js:272-281](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L272-L281)), plus 3 timer-based copies in `reading.js` ([reading.js:279-287](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L279-L287), [reading.js:345-356](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L345-L356), [reading.js:594-601](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L594-L601)).
  - `appendBinary`: 2 copies ([vault.js:231-240](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L231-L240), [vault.js:574-582](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L574-L582)).
  - Reading and parsing the `.base` file: 2 copies ([bases.js:306-319](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L306-L319), [bases.js:340-355](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L340-L355)); `basesView.open` calls both, reading the file twice ([bases.js:372-375](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L372-L375)).
  - The row-click filter in `Setting`: 2 copies ([interface.js:726-729](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L726-L729), [interface.js:742-745](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L742-L745)).
  - The size clamp `Math.max(200, Math.min(4000, ...))`: 3 copies ([reading.js:401](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L401), [reading.js:583](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L583)).
  - Leaf placement: 2 copies (LSP-RUNTIME-04). The page under the top setting page: 2 copies (SRP-RUNTIME-06).
- **Why it matters:** the copies already differ. Some coalescers check `runtime.app` and some do not ([plugins.js:1010](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1010), [plugins.js:1058](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1058)). One deduplicates by signature; the others resend unchanged state.
- **Fix direction:** `messageOf(error)`, `coalescedNotifier(operationName, buildPayload, { delayMilliseconds, isDeduplicated })`, one `appendBytes`, one `readBaseDefinition`, one `ignoresControlClicks(listener)`, and named view size limits.

#### CC-RUNTIME-03 Timers stand in for ordering and are never cancelled
- **Severity:** Medium
- **Evidence:**
  - Polling for a prototype patch at 250, 1000, 3000 and 8000 ms after every plugin load and at layout-ready ([plugins.js:1021-1023](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1021-L1023), [plugins.js:627](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L627), [plugins.js:1286](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1286)).
  - "Give it a moment" zero-delay waits ([plugins.js:1105-1106](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1105-L1106), [reading.js:722](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L722)).
  - A 150 ms close after blur ([interface.js:1056](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L1056)) and a 50 ms frame fallback ([dom-extensions.js:337-346](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-dom-extensions.js#L337-L346)).
  - Race timers that are never cleared, one per call ([reading.js:380-382](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L380-L382), [plugins.js:1146-1149](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1146-L1149)).
  - 17 own-code `setTimeout` calls in all (`grep "setTimeout\("`, vendor lines excluded).
- **Why it matters:**
  - A plugin that patches `setViewState` after 8 s is never noticed.
  - A paste handler that finishes after one macrotask is reported as not handled, so Graphite pastes as well and the text appears twice.
  - Each keystroke with suggestions leaves a 3 s timer alive. WebKit throttles timers of a page outside a window ([Architecture.md:349](../../../Docs/Architecture.md#L349)), which stretches every one of these waits unpredictably.
- **Fix direction:**
  - Detect the patch at the moment it matters: the host asks `file.openInView`, which already probes.
  - Let paste handlers return or register a promise the runtime awaits with an explicit bound.
  - Clear race timers with one `withTimeout(promise, milliseconds)` primitive.

#### CC-RUNTIME-04 About twenty durations, sizes and counts are unnamed literals
- **Severity:** Low
- **Evidence:**
  - Durations: notice default 4500 ms and 1000 ms grace ([interface.js:306](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L306), [interface.js:320](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L320)); 200 ms link resolution ([metadata.js:529](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L529)); 2000 ms `requestSave` ([workspace.js:531](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L531)); 150 ms style and 50 ms resize delays ([reading.js:355](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L355), [reading.js:600](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L600)); 3000 ms save bound ([reading.js:668](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L668)).
  - Sizes: 65536-character view state ([workspace.js:811](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L811)); 4000-character stack ([plugins.js:642](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L642)); view sizes 700, 600 and 320 ([reading.js:579](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L579)).
  - Counts: 3 `process` attempts ([vault.js:265](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L265), [vault.js:275](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L275), [vault.js:279](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L279)); 100000 name candidates ([vault.js:520](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L520), [vault.js:707](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L707)).
- **Why it matters:** the `process` limit is written as both `3` and `2` (`attempt === 2`), so changing one silently breaks the conflict report. The view state limit is a persistence contract with the host.
- **Fix direction:** named constants with units beside the existing good ones (`maximumIndexedNoteBytes`, `snapshotDelayMilliseconds`).

#### CC-RUNTIME-05 A retry decision and several tests depend on message or source text
- **Severity:** Medium
- **Evidence:**
  - `processNow` retries only when the error text matches `/changed outside this plugin/` ([vault.js:279](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L279)). That text is built by `conflictError` ([vault.js:70-72](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L70-L72)).
  - Tests assert on error text ([vault.test.js:51](../../../Tests/CommunityPluginRuntimeTests/tests/vault.test.js#L51), [editor-commands.test.js:127](../../../Tests/CommunityPluginRuntimeTests/tests/editor-commands.test.js#L127)) and on the CSS file's source text ([themes.test.js:139-143](../../../Tests/CommunityPluginRuntimeTests/tests/themes.test.js#L139-L143)).
- **Why it matters:** rewording the user-facing conflict sentence disables the retry and turns every concurrent `process` into a plugin-visible failure. No test covers the retry path with a wording change.
- **Fix direction:** a `WriteConflictError` class (or `kind: 'conflict'`) tested by type. Tests assert on error kinds and on computed styles, not on text.

#### CC-RUNTIME-06 Failed writes and failed reads are swallowed into logs or empty values
- **Severity:** Medium
- **Evidence:**
  - `hostBridge.notify` turns every failure into `console.error` ([foundation.js:46-48](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L46-L48)). It carries writes: `secrets.set` ([foundation.js:689-693](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L689-L693)) and `appearance.setConfig` ([vault.js:627-630](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L627-L630)).
  - An unreadable or invalid `.base` file yields `{}` options ([bases.js:316-318](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L316-L318), [bases.js:352-354](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L352-L354)).
  - View saves that fail are logged and counted as saved ([reading.js:668](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L668)).
- **Why it matters:**
  - `SecretStorage.setSecret` updates memory and fires `change` before the keychain write is known to succeed, so a plugin's API key is lost on the next start with no message.
  - A broken `.base` shows a plugin view with default settings as if it were the file's.
- **Fix direction:** writes use `send` and surface failure to the caller (`setSecret` returns a promise, as Obsidian's does not, so at least report through `plugin.failure`). A failed read becomes a visible error state in the view.

#### CC-RUNTIME-07 Comments narrate history or contradict the code
- **Severity:** Low
- **Evidence:**
  - The `bases.js` header says plugin views are "not offered among a base's views; registering one is reported as unsupported" ([bases.js:1-4](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L1-L4)), while the same file implements them ([bases.js:267-411](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L267-L411)) and `Plugin.registerBasesView` registers them ([plugins.js:521-533](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L521-L533)).
  - The doc comment for `notifyLeavesChanged` sits above the `protocolHandlers` getter ([workspace.js:800-805](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L800-L805)).
  - Comments narrate project history: "Theme Phase 3" ([graphite-default-variables.css:188](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L188)) and "as requiring it used to" ([plugins.js:149](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L149)).
  - The layer header says "Version: 4" ([graphite-default-variables.css:11-12](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L11-L12)); the resolver uses 5 ([ThemeTokenResolver.swift:38](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L38)).
- **Why it matters:** the next session will trust the header and remove or duplicate working Bases code. The version line is a fact with two owners that already disagree.
- **Fix direction:** headers state what the file does now. Phase names go to commit messages. The layer version is declared once (in Swift) and the CSS comment points to it.

#### CC-RUNTIME-08 Conditionals with identical branches
- **Severity:** Low
- **Evidence:**
  - `if (fence || isInMathBlock || isInComment) closeSection(...); else closeSection(...)` with identical branches ([metadata.js:262-263](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L262-L263)).
  - `element.createDiv ? element : element` ([workspace.js:954](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L954)).
  - `!newLeaf || newLeaf === false` ([workspace.js:848](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L848)).
- **Why it matters:** each reads as a distinction the code does not make. The first hides whether unterminated fences should close differently, which is a parser question.
- **Fix direction:** collapse each to its single branch, or implement the intended difference with a test.

#### CC-RUNTIME-09 Two default style layers disagree, and one contradicts its own header
- **Severity:** Medium
- **Evidence:**
  - `runtime.css` says its variables are set with no specificity so a theme's `.theme-dark` wins ([runtime.css:1-4](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L1-L4)), yet it sets variables in `body { … }` ([runtime.css:226-238](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L226-L238)) and `body.theme-dark { … }` ([runtime.css:239](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L239)). The latter outranks a theme's `.theme-dark` rule.
  - It redefines, with different values, variables the shared layer defines: the accent (211 vs 258: [runtime.css:34](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L34), [graphite-default-variables.css:37](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L37)), the base colour scale ([runtime.css:51-77](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L51-L77), [graphite-default-variables.css:65-87](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L65-L87)), the named colours and their RGB triples, `--font-text` and `--font-interface` ([runtime.css:12-14](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L12-L14), [graphite-default-variables.css:21-23](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L21-L23)), `--callout-radius` and `--code-background`.
  - The callout type list exists in both files with different specificity ([runtime.css:241-252](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L241-L252), [graphite-default-variables.css:174-186](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L174-L186)).
  - The block copy page loads both ([CommunityPluginReadingBlocks.swift:409-410](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L409-L410)); the theme resolver loads only the shared layer ([ThemeTokenResolver.swift:129](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L129), [ThemeTokenResolver.swift:142](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L142)).
- **Why it matters:** native notes and plugin copies start from different defaults, so the same theme draws a note and a plugin block inside it differently. BUG-RUNTIME-04 is one concrete case.
- **Fix direction:** `runtime.css` holds panel layout and Obsidian class styling only. Every variable default lives in the shared layer, and Graphite's own look is written as `:where` overrides there.

#### CC-RUNTIME-10 81 own-code lines exceed 160 characters
- **Severity:** Low
- **Evidence:** `grep "^.{161,}$"` over the runtime's own `.js` files, vendor lines excluded:

  | File | Lines |
  | --- | ---: |
  | `plugins.js` | 20 |
  | `reading.js` | 15 |
  | `workspace.js` | 10 |
  | `metadata.js` | 8 |
  | `vault.js` | 8 |
  | `settings.js` | 6 |
  | `dom-extensions.js` | 5 |
  | `interface.js` | 5 |
  | `bases.js` | 2 |
  | `foundation.js` | 1 |
  | `host-connection.js` | 1 |

  The longest is [vault.js:609](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L609).
- **Why it matters:** long lines hide conditions inside expressions, for example the leaf fallback at [workspace.js:685](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L685).
- **Fix direction:** a formatter with a 160-character limit, run by the Node test script.

#### CC-RUNTIME-11 Every create, delete or rename re-resolves every link in the vault
- **Severity:** Medium
- **Evidence:**
  - `scheduleLinkResolution` runs `resolveAllLinks` 200 ms after each `create`, `delete` or `rename` ([metadata.js:524-530](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L524-L530), [metadata.js:605](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L605), [metadata.js:618](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L618), [metadata.js:631](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L631)). That rebuilds both maps for every note and triggers `resolve` once per note ([metadata.js:514-522](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L514-L522)).
  - `getBacklinksForFile` resolves every reference of every note on each call ([metadata.js:413-421](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L413-L421)).
- **Why it matters:** OBJECTIVE.md sets 10,000 and 100,000 notes as validation workloads. One new note in a 10,000-note vault fires 10,000 `resolve` events into every listening plugin. This runs in WebKit's process, but it competes with live views and Pencil input there.
- **Fix direction:** re-resolve only notes whose unresolved links name the changed file's name (an index from unresolved link name to source paths), and fire `resolve` for those.

#### CC-RUNTIME-12 The HTML sanitizer is a deny list
- **Severity:** Medium
- **Evidence:** `sanitizeHTMLToDom` removes nine element names, `on*` attributes and `javascript:` values ([foundation.js:494-513](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L494-L513)). It keeps `area` and every other element and attribute. The page's link guard handles only `a` ([reading.js:747](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L747)).
- **Why it matters:** the sanitizer renders note content (sections, embedded notes) into the page whose plugins hold the vault bridge. Any element the list forgot is a way out of it. BUG-RUNTIME-05 is one.
- **Fix direction:** an allow list of elements and attributes for rendered Markdown, with URL attributes limited to `http`, `https`, `mailto`, the vault resource scheme and fragment links. The link guard covers `area` too.

## 5. Defects and latent bugs

#### BUG-RUNTIME-01 A plugin's asynchronous edit lands in the note the person switched to
- **Trigger:** the person runs a plugin command on note A whose `editorCallback` awaits something (a modal, a network request, a file read) and then edits through the `editor` it was given. While it waits, the person switches to note B (another tab or another note).
- **Path:**
  1. The host sends `command.run` with A's editor snapshot ([CommunityPluginHost.swift:660](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L660)).
  2. `setActiveDocument` stores it in the mirror leaf's one `SnapshotEditor` ([plugins.js:1376](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1376), [workspace.js:767](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L767), [workspace.js:782-788](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L782-L788)).
  3. `executeCommand` hands that object to the plugin ([plugins.js:213-222](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L213-L222)).
  4. The switch makes the host send `workspace.activeDocument` with B's snapshot ([CommunityPluginHost.swift:716-719](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L716-L719)). `setActiveDocument` keeps the same `MarkdownView` ([workspace.js:762](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L762)) and calls `adoptSnapshot` on the same editor object ([workspace.js:785](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L785)), which now holds B's path, text and identifier ([workspace.js:163-174](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L163-L174)).
  5. The plugin's continuation calls `replaceRange` or `replaceSelection` with positions computed against A ([workspace.js:266-277](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L266-L277)). `flush` sends `editor.apply` for B ([workspace.js:383-390](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L383-L390)).
  6. The host finds B's snapshot matching B's text and applies the edit ([CommunityPluginHost.swift:768-788](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L768-L788)).
- **Effect:** text meant for A is inserted into B at positions clamped to B's lines ([workspace.js:194-199](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L194-L199)), as one undoable edit; A is unchanged. In Obsidian each tab has its own view and editor, so the edit would go to A or fail.
- **Platforms / reach:** iPad, iPhone and Mac; normal path for any asynchronous editor command (Templater, QuickAdd, AI plugins). The Node fake would not catch it (LSP-RUNTIME-01).
- **Confidence:** Traced.

#### BUG-RUNTIME-02 Keyboard shortcuts plugins register with the `Mod` modifier never fire
- **Trigger:** a plugin registers a key in a modal or suggestion scope with Obsidian's platform modifier, for example `this.scope.register(['Mod'], 'Enter', submit)`, and the person presses Command-Return on a hardware keyboard.
- **Path:**
  1. `Scope.register` stores the modifiers as the sorted, joined strings the plugin passed, here `'Mod'` ([interface.js:126-130](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L126-L130)).
  2. The modal's capture listener calls `scope.handleKeyEvent` ([interface.js:364](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L364)).
  3. That function compares the stored string with `Keymap.modifiersOf(event)`, which yields only `Alt`, `Ctrl`, `Meta` and `Shift`, here `'Meta'` ([interface.js:134-139](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L134-L139), [interface.js:163-170](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L163-L170)).
  4. `'Mod' !== 'Meta'`, no handler matches, and the parent scope answers `false`.
- **Effect:** the plugin's shortcut does nothing. Combinations such as `['Mod', 'Shift']` fail the same way. `Keymap.isModifier` maps `Mod` to Command ([interface.js:171-174](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L171-L174)), but `Scope` does not use it.
- **Platforms / reach:** iPad and iPhone with a hardware keyboard, and Mac. No test covers `Scope` (§2).
- **Confidence:** Traced.

#### BUG-RUNTIME-03 A plugin view opened in the current tab never appears and is never closed
- **Trigger:** a plugin opens its view with `app.workspace.getLeaf(false)` (or `getLeaf()`, `getUnpinnedLeaf()`, `getMostRecentLeaf()`) followed by `setViewState({ type: MY_VIEW, active: true })`, while a note is focused.
- **Path:**
  1. `getLeaf(false)` returns the mirror leaf `markdownLeaf` when the note is active ([workspace.js:847-851](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L847-L851)).
  2. `setViewState` builds the plugin's view and opens it into the mirror leaf's element ([workspace.js:609-620](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L609-L620), [workspace.js:626-633](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L626-L633)). That element is never placed in the page: the mirror leaf is constructed directly, not through `createPluginLeaf` ([workspace.js:717](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L717)).
  3. `revealLeaf` returns at once for the mirror leaf ([workspace.js:900-901](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L900-L901)). `notifyLeavesChanged` lists `pluginLeaves` only ([workspace.js:818](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L818)), and `showIfNew` returns for kind `mirror` ([workspace.js:649](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L649)). The host never hears of the view.
  4. On the next focus message, `setActiveDocument` replaces the view with a new `MarkdownView` without closing it ([workspace.js:762](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L762), or [workspace.js:772](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L772) for other files).
- **Effect:**
  - The command does nothing visible.
  - The plugin's view stays loaded: its registered intervals and events keep running until the plugin unloads.
  - Until the next focus message, `getActiveViewOfType(MarkdownView)` answers `null`, so editor commands report "not available here".
- **Platforms / reach:** iPad, iPhone and Mac; normal path for plugins that open their view "in the current tab".
- **Confidence:** Traced.

#### BUG-RUNTIME-04 A theme's text and interface fonts do not reach plugin pages or block copies
- **Trigger:** the vault's Obsidian theme sets its fonts the way Obsidian's documentation describes, through `--font-text-theme` or `--font-interface-theme`, and a plugin draws a block or view.
- **Path:**
  1. The shared layer derives `--font-text` from `--font-text-theme` ([graphite-default-variables.css:18-23](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L18-L23)). The theme resolver measures against that layer alone ([ThemeTokenResolver.swift:129](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L129), [ThemeTokenResolver.swift:142](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L142)), so native notes take the theme's font.
  2. The runtime page and the copy page also load `runtime.css` after the layer ([index.html:9-10](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/index.html#L9-L10), [CommunityPluginReadingBlocks.swift:409-410](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L409-L410)).
  3. `runtime.css` sets `--font-interface`, `--font-text` and `--font-monospace` to literal system fonts at equal (zero) specificity, later in source order ([runtime.css:11-14](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L11-L14)). The `-theme` variables the theme set are no longer referenced.
- **Effect:** inside a themed note, a plugin block (Dataview table, Tasks list) and every plugin view draw in the system font while the surrounding note uses the theme's font.
- **Platforms / reach:** iPad, iPhone and Mac; any theme that sets fonts through the `-theme` variables rather than overriding `--font-text` itself.
- **Confidence:** Partly traced: the runtime and copy pages were followed. Which variables a given theme sets was not read (no theme ships in the snapshot's runtime folder).

#### BUG-RUNTIME-05 An image-map link in a rendered note can navigate the plugins' page away
- **Trigger:** a note contains raw HTML with an image map (`<map><area href="https://example.com" ...></map>` over an image), the note is rendered for plugins (a section a post-processor changes, or an embedded note in a plugin view), and the person taps the area.
- **Path:**
  1. The host renders the note's Markdown to HTML ([CommunityPluginHost.swift:878-886](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L878-L886), [CommunityPluginEditorChange.swift:44-51](../../../Sources/GraphiteCore/CommunityPluginEditorChange.swift#L44-L51)).
  2. `drawSection` inserts it through `sanitizeHTMLToDom` ([reading.js:498-500](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L498-L500)), which keeps `area` and its `href` ([foundation.js:494-509](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L494-L509)).
  3. A tap in the copy is replayed as `element.click()` on the area ([reading.js:719](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L719), [reading.js:534](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L534)).
  4. The page-wide guard looks only for `closest('a')` ([reading.js:747-748](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L747-L748)), so the area's default navigation runs.
- **Effect:** the runtime page navigates away and every running plugin ends, the outcome the guard's own comment says it exists to prevent ([reading.js:741-743](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L741-L743)).
- **Platforms / reach:** iPad, iPhone and Mac; rare content (raw HTML image maps).
- **Confidence:** Partly traced: that swift-markdown's `HTMLFormatter` passes raw HTML blocks through was not read in the vendored library. The navigation decision itself belongs to the host's navigation delegate, also not read.

#### BUG-RUNTIME-06 A note's cached metadata can end older than its file
- **Trigger:** a note changes twice in quick succession (two saves, or a plugin write and an external change), so two `modify` events queue two reads of the same file.
- **Path:**
  1. Each `modify` enqueues a read ([metadata.js:607-609](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L607-L609)).
  2. The queue runs up to four reads at once with no per-path ordering ([metadata.js:562-572](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L562-L572)).
  3. Each read stores its result when its reply arrives ([metadata.js:576-580](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L576-L580)). The only staleness check compares file objects, not request order ([metadata.js:578](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L578)).
- **Effect:** if the older read's reply arrives last, `getFileCache` returns the earlier version's headings, tags and links until the next change, and plugins receive `changed` with the older text after the newer one.
- **Platforms / reach:** iPad, iPhone and Mac; only when replies reorder.
- **Confidence:** Partly traced: whether the host's vault bridge can answer two reads of one path out of order was not settled ([CommunityPluginHost.swift:860-866](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L860-L866) calls `bridge.respond`, whose concurrency was not read).

#### BUG-RUNTIME-07 `app.getTheme()` answers dark on a light page
- **Trigger:** a plugin asks `app.getTheme()` to choose its colours while Graphite shows the light appearance, in a vault whose settings hold no `theme` key, or the value `system`, Obsidian's default.
- **Path:**
  1. `getTheme` returns `moonstone` only when `vault.getConfig('theme')` is exactly `'moonstone'` ([plugins.js:920-922](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L920-L922)).
  2. `getConfig` falls back to Obsidian's default `'system'` ([vault.js:613-618](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L613-L618), [vault.js:82](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L82)).
  3. `getTheme` therefore answers `'obsidian'` (dark), while the page carries `theme-light` ([plugins.js:1235-1240](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1235-L1240)) and `isDarkMode()` answers `false` ([plugins.js:919](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L919)).
- **Effect:** a plugin that styles by `getTheme()` draws dark-theme colours on the light page and in its copies. The code's own comment says Graphite's appearance decides ([plugins.js:920-921](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L920-L921)).
- **Platforms / reach:** iPad, iPhone and Mac in light appearance.
- **Confidence:** Partly traced: the contents of `appearanceConfiguration` sent by the host ([plugins.js:1259](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1259)) were not read in Swift. A vault whose `appearance.json` holds `"theme": "obsidian"` reproduces it in every case.

## 6. What to keep

| # | Design | Evidence | Why it is sound |
| --- | --- | --- | --- |
| 1 | Writes state their expectation: `revision` after a read or write, `replace` otherwise, `absent` for `create`. A conflict is refused, reported as `plugin.writeConflict` and thrown, never overwritten. | [vault.js:172-196](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L172-L196), [vault.js:545-549](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L545-L549); test [vault.test.js:44-57](../../../Tests/CommunityPluginRuntimeTests/tests/vault.test.js#L44-L57) | This is OBJECTIVE.md's "never silently overwrite another application's changes", applied to plugins. |
| 2 | Same-path writes run in turn, each expecting the revision the previous one left; the expectation is read when the turn comes. | [vault.js:197-216](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L197-L216); test [obsidian-conventions.test.js:121-143](../../../Tests/CommunityPluginRuntimeTests/tests/obsidian-conventions.test.js#L121-L143) | Matches Obsidian's last-write-wins for one plugin's quick saves without weakening the conflict check against others. |
| 3 | `process` re-reads and re-applies on conflict, and skips the write when the text is unchanged. | [vault.js:248-283](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L248-L283); tests [vault.test.js:59-90](../../../Tests/CommunityPluginRuntimeTests/tests/vault.test.js#L59-L90) | The transform always applies to the current file, and an unchanged note is never rewritten (RULES.md: indexing and preview must not rewrite files). |
| 4 | An unreadable `types.json` is not overwritten: a failed `process` writes only when the file does not exist. | [plugins.js:776-781](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L776-L781) | Unreadable data is left alone, the rule the synthesis states. |
| 5 | Missing Obsidian settings files read as `{}` and nothing is written until a plugin writes. | [vault.js:154-165](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L154-L165) | Opening a vault with plugins creates no files the person did not ask for. |
| 6 | The host transport is the one injected seam, with a Node harness that loads the real page in `index.html` order against a temporary folder. | [foundation.js:30-49](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L30-L49), [host-connection.js:13](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-host-connection.js#L13), [runtime-harness.js:95-106](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L95-L106) | Tests exercise production scripts, not copies. The harness keeps jsdom's own errors apart from page errors ([runtime-harness.js:36-40](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L36-L40)). |
| 7 | Vault reads and listings are answered as JSON text parsed in WebKit, not on the app's main thread. | [host-connection.js:11-13](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-host-connection.js#L11-L13), [CommunityPluginHost.swift:860-866](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L860-L866) | Keeps large notes and listings off the main thread (RULES.md concurrency). |
| 8 | Unsupported APIs throw a named error and are reported once per plugin and feature. | [foundation.js:51-110](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L51-L110) | No fake success: RULES.md's "accurately communicate why it is unavailable". |
| 9 | Desktop modules are stand-ins that fail only when used, saying which member was reached. | [plugins.js:145-184](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L145-L184); test [plugin-loading.test.js:99](../../../Tests/CommunityPluginRuntimeTests/tests/plugin-loading.test.js#L99) | Cross-platform plugins load on mobile as in Obsidian mobile, and failures stay visible. |
| 10 | ES5-compiled plugins can extend ES2015 classes through `callableClass`, with the class's own prototype, so `instanceof` is exact. | [plugins.js:47-85](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L47-L85); test [obsidian-conventions.test.js:12](../../../Tests/CommunityPluginRuntimeTests/tests/obsidian-conventions.test.js#L12) | Execution compatibility without patching plugin code (OBJECTIVE.md's plugin goal). |
| 11 | Plugin attribution through `sourceURL` where stacks show it and blob addresses where they do not, decided by a probe. | [plugins.js:93-143](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L93-L143), [foundation.js:64-93](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L64-L93) | Failures and unsupported features name the right plugin in WebKit and in V8 alike. |
| 12 | Metadata reads are bounded: 4 MiB per note, 4 at once, cloud-only notes skipped, only metadata kept. | [metadata.js:14-18](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L14-L18), [metadata.js:574-587](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L574-L587); test [metadata-cache.test.js:107](../../../Tests/CommunityPluginRuntimeTests/tests/metadata-cache.test.js#L107) | OBJECTIVE.md: no uncontrolled cloud downloads, no whole vault in memory. |
| 13 | Positions are in UTF-16 code units, as CodeMirror and `NSString` count. | [metadata.js:37-45](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L37-L45), [workspace.js:194-210](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L194-L210); test [editor-commands.test.js:54](../../../Tests/CommunityPluginRuntimeTests/tests/editor-commands.test.js#L54) | Edits computed in the runtime land at the same place in Graphite's editor. |
| 14 | Editor changes made in one synchronous turn reach the host as one change. A refused change brings the current note back, and a newer local change is not overwritten by an older answer. | [workspace.js:365-396](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L365-L396); tests [editor-commands.test.js:28-52](../../../Tests/CommunityPluginRuntimeTests/tests/editor-commands.test.js#L28-L52), [editor-commands.test.js:157-196](../../../Tests/CommunityPluginRuntimeTests/tests/editor-commands.test.js#L157-L196) | One undoable edit per command, and no edit applies to text the plugin did not see. |
| 15 | `dom-extensions.js` never replaces an existing member. | [dom-extensions.js:7-15](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-dom-extensions.js#L7-L15) | WebKit's own `Array.prototype.findLast`-style members win; the runtime adds only what is missing. |
| 16 | `runtime.receive` never throws: unknown operations and handler failures become `{ failure: { kind, message } }`. | [plugins.js:1541-1550](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1541-L1550) | The host always gets an answer it can read. |
| 17 | Copies are bounded and deduplicated: 4 MiB per copy, 60 ms gathering, a signature check before sending, a theme dropped from copies before the 3 MiB style budget is exceeded. | [reading.js:17-25](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L17-L25), [reading.js:289-294](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L289-L294), [reading.js:300-323](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L300-L323); test [themes.test.js:115-127](../../../Tests/CommunityPluginRuntimeTests/tests/themes.test.js#L115-L127) | A runaway plugin cannot build an unbounded message to the app. |
| 18 | A section is kept as the plugin's only when the plugin changed what it shows; otherwise Graphite keeps its native rendering. | [reading.js:493-513](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L493-L513) | Native rendering and responsiveness stay the default. |
| 19 | Task checkboxes in sections are mapped to their note lines, so the host ticks the task in the note. | [reading.js:468-481](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L468-L481), [reading.js:713-715](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L713-L715) | The edit goes through Graphite's editor, not a plugin write. |
| 20 | Links in plugin content go through the host; `window.open` accepts only `http`, `https` and `mailto`. | [reading.js:744-765](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L744-L765), [host-connection.js:32-41](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-host-connection.js#L32-L41); test [reading-blocks.test.js:91](../../../Tests/CommunityPluginRuntimeTests/tests/reading-blocks.test.js#L91) | The page is never replaced by an anchor link, and other schemes are refused. |
| 21 | Listener-gated host work: the host sends typing, menus and paste only while some plugin listens. | [workspace.js:728-745](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L728-L745), [plugins.js:1053-1066](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1053-L1066) | Protects editor responsiveness when no plugin cares (OBJECTIVE.md priority). |
| 22 | A new page per vault start: every module-level registry lives exactly as long as one vault's session. | [CommunityPluginHost.swift:371-401](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L371-L401) | Vault-switch cleanup needs no per-feature code in the runtime. |
| 23 | The shared variable layer is all zero-specificity `:where` rules. | [graphite-default-variables.css:8-9](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L8-L9) | A theme overrides every default, as in Obsidian. |
| 24 | Named limits with units: `maximumIndexedNoteBytes`, `concurrentNoteReads`, `pluginScriptLoadMilliseconds`, `suggestionWaitMilliseconds`, `maximumSnapshotCharacters`, `snapshotDelayMilliseconds`, `processorWaitMilliseconds`, `maximumCopyStyleCharacters`. | [metadata.js:16-18](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L16-L18), [plugins.js:108](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L108), [plugins.js:1048](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1048), [reading.js:19-25](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L19-L25), [reading.js:300](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L300) | The model for CC-RUNTIME-04's fix. |
| 25 | Naming follows RULES.md: `pluginIdentifier`, `normalizedPath`, `eventReference`, `isReloadNeeded`; abbreviations appear only where Obsidian's API names them (`cls`, `attr`, `ctime`, `docId`). Comments mostly state the current rule with the plugin that needs it. | for example [vault.js:197-200](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L197-L200), [workspace.js:644-647](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L644-L647) | Each compatibility shim says which plugin it exists for, which keeps cleanup from deleting it. |

## 7. Blueprint for this area

### Target shape

The page keeps classic scripts loaded in order, because the Node harness evaluates them that way and WebKit needs no build step. Each file now owns one object and registers its pieces through a small set of explicit seams.

| Unit (file) | Single responsibility | Seam |
| --- | --- | --- |
| `host-channel.js` | `send`/`notify` with generated operation constants and payload checks; `notifyOrReport` for writes | **Port** (`HostChannel`): replaced by the Node fake; real substitution |
| `host-message-router.js` | `register(operation, handler)`, `receive` | Plain object |
| `plugin-attribution.js` | source-name and blob attribution | Plain functions |
| `unsupported-features.js` | report once, fail visibly | Plain functions |
| `coalesced-notifier.js` | microtask or timed coalescing, signature deduplication, `withTimeout` | Primitive used by every notifier |
| `dom-extensions.js`, `foundation.js` (utilities only) | Obsidian's helpers | unchanged |
| `vault.js` → `vault-tree.js`, `data-adapter.js`, `path-write-queue.js`, `vault-configuration.js`, `file-manager.js` | tree mirror; revision-checked I/O; one queue per path; configuration merge; file manager | `DataAdapter` takes a `HostChannel` |
| `metadata.js` → `note-parser.js`, `link-resolver.js`, `note-read-queue.js`, `metadata-cache.js` | parse; resolve; latest-read-wins queue; Obsidian API | pure parser and resolver, testable without a page |
| `workspace.js` → `snapshot-editor.js`, `focus-mirror.js`, `leaf-host-state.js`, `workspace.js` | per-note editors; focus mirroring; leaf presentation enum; Obsidian API | none beyond `HostChannel` |
| `interface.js` → `keyboard-scopes.js`, `plugin-panel.js`, `notices.js`, `modals.js`, `setting-controls.js`, `suggestions.js`, `menus.js` | one each | `PanelContent` enum in `plugin-panel.js` |
| `plugins.js` → the ten files of §3.2 | one each | handlers through `host-message-router.js` |
| `reading.js` → the seven objects of §3.5 | one each | `listener-marking.js` is the single allow-listed global patch |
| `graphite-default-variables.css` | every variable default | shared with the theme resolver; version declared once in Swift |
| `runtime.css` | panel layout and Obsidian class styling, no variable defaults | none |
| `community-plugin-messages.json` (new resource) | operation names and payload fields for both directions | generates the Swift enum, the runtime constants and the fake host switch |

No new protocol is introduced beyond `HostChannel`, which already has two implementations (WebKit, Node).

### Ordered steps (each leaves the app building and behaving the same)

1. **Fix the four traced and highest-value defects first, each with a Node test written to fail first.**
   - BUG-RUNTIME-01: one `SnapshotEditor` per note path. `setActiveDocument` creates a new editor for a different path instead of adopting into the old one.
   - BUG-RUNTIME-02: map `Mod` to `Meta` on Apple platforms in `Scope.register`.
   - BUG-RUNTIME-03: `getLeaf(false)` returns a plugin tab leaf for non-Markdown view types; or `setViewState` on the mirror leaf moves the view into a new tab leaf.
   - BUG-RUNTIME-07: `getTheme` reads the body class.
2. **Make the fake host keep production semantics** (LSP-RUNTIME-01, LSP-RUNTIME-02):
   - text-compared snapshots, `snapshot` on refusal, read-only refusal;
   - `vault.changes` with only `{ path, isReloadNeeded }`.
   - Adjust the rename test to production's contract, or add moves to the host first.
3. **Add `coalesced-notifier.js` and `messageOf(error)`.** Replace the 10 coalescer copies and the 15 error-text copies one at a time (CC-RUNTIME-02). Behaviour is unchanged: the same operation, payload and microtask timing.
4. **Introduce `host-message-router.js`.** Move each handler's registration into its own file while keeping the names, so `plugins.js` no longer merges `basesMessageHandlers` and `reading.js` no longer mutates `messageHandlers` (OCP-RUNTIME-03).
5. **Write `community-plugin-messages.json` from the 83 names in §8.** Generate the runtime constants and the fake host's switch, and add a contract test that every declared host-to-runtime operation has a registered handler. The Swift generation follows in the host's area.
6. **Split `plugins.js` along §3.2, one file per commit**, adding each to `index.html` in the position its dependencies need; the harness picks the order up from `index.html`.
7. **Split `reading.js` along §3.5.** Confine the `EventTarget` patch to elements in the reading area and plugin leaves (DIP-RUNTIME-03), with a test that a listener on `document` gains no attribute.
8. **Replace leaf flags with `LeafHostState`** (SRP-RUNTIME-04) and the panel fields with `PanelContent` (SRP-RUNTIME-06).
9. **Vault:** one `PathWriteQueue` for every write and append, and every removal delegated to the adapter (SRP-RUNTIME-05). Replace the message-text retry with an error kind (CC-RUNTIME-05).
10. **Metadata:** `NoteReadQueue` keeps only the latest read per path (BUG-RUNTIME-06). Incremental link resolution (CC-RUNTIME-11). Split `parseBody` (CC-RUNTIME-01) behind the existing position tests.
11. **CSS:** move every variable default from `runtime.css` into the shared layer as `:where` rules, remove the specificity rules, and bump the layer version once in Swift (CC-RUNTIME-09, BUG-RUNTIME-04).
12. **Sanitizer:** an allow list, and the link guard on `a, area` (CC-RUNTIME-12, BUG-RUNTIME-05).

### Behaviour that must be preserved

| ID | Invariant | Evidence | Test idea |
| --- | --- | --- | --- |
| RUNTIME-INV-01 | Scripts run in the order `index.html` lists them; the Node harness reads that list. | [index.html:12-26](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/index.html#L12-L26), [runtime-harness.js:14-17](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L14-L17) | Load the page with each file's declared dependencies checked at load: a missing dependency throws a named error. |
| RUNTIME-INV-02 | A plugin's code is attributed by the source name `plugin:<id>/main.js` or by its blob address; `UnsupportedFeature` reports carry that identifier. | [plugins.js:110-118](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L110-L118), [foundation.js:76-92](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L76-L92) | A plugin calling an unsupported API produces exactly one report naming it, in both evaluation modes. |
| RUNTIME-INV-03 | A write expects `revision` after a read or write of that path, `replace` otherwise; `create` expects `absent`; a refused write is never retried as `replace`. | [vault.js:174-177](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L174-L177), [vault.js:549](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L549) | Read, change on disk, modify: the file keeps the disk version and one `plugin.writeConflict` is sent (exists). |
| RUNTIME-INV-04 | Writes to one path from this runtime run in call order; the last one's content stays. | [vault.js:201-209](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L201-L209) | Two unawaited `saveData` calls: the file holds the second (exists); add the same for `write` mixed with `process`. |
| RUNTIME-INV-05 | `process` tries at most three reads, applies the transform to the latest text, writes nothing when the text is unchanged, and reports a conflict only on the last attempt. | [vault.js:262-283](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L262-L283) | A host that changes the file on the first two reads: the third write succeeds and no conflict is reported. |
| RUNTIME-INV-06 | Paths with any component starting with `.` never appear in the file tree or its events, yet the adapter reads and writes them. | [vault.js:56-58](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L56-L58), [vault.js:382](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L382), [vault.js:417](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L417) | Exists in `vault.test.js` ("hidden files"); keep. |
| RUNTIME-INV-07 | Missing `<configDir>/app.json`, `appearance.json` and `hotkeys.json` read as `{}` and are not created. | [vault.js:158-165](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L158-L165) | Exists ([obsidian-conventions.test.js:145](../../../Tests/CommunityPluginRuntimeTests/tests/obsidian-conventions.test.js#L145)); assert the files still do not exist afterwards. |
| RUNTIME-INV-08 | Plugin settings live at `<manifest.dir or configDir/plugins/<id>>/data.json`, written as `JSON.stringify(data, null, 2)`; an empty file loads as `null`. | [plugins.js:389-404](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L389-L404) | Golden file comparison after `saveData({ a: 1 })`. |
| RUNTIME-INV-09 | `types.json` keeps its other keys, merges `types`, is written with two-space JSON, and batches types set without awaiting into one save. | [plugins.js:754-782](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L754-L782) | Exists ([vault.test.js:92](../../../Tests/CommunityPluginRuntimeTests/tests/vault.test.js#L92)); add a file with an extra top-level key. |
| RUNTIME-INV-10 | `processFrontMatter` writes nothing for an unchanged object, keeps the note's CRLF line endings, dumps YAML with no line wrapping, and parses with the core schema (dates stay text). | [vault.js:720-735](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L720-L735), [foundation.js:330-339](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L330-L339) | CRLF note with `date: 2024-05-01`; touch another key; the date stays unquoted text and every line ends in CRLF. |
| RUNTIME-INV-11 | Metadata and editor positions are `{ line, col/ch, offset }` in UTF-16 code units. | [metadata.js:37-45](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L37-L45), [workspace.js:194-210](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L194-L210) | Exists for the editor (emoji test); add one for metadata headings after an emoji. |
| RUNTIME-INV-12 | Link resolution order: beside the note, then from the root, then by name or path suffix ignoring case, shortest path first. | [metadata.js:446-471](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L446-L471) | Exists ([metadata-cache.test.js:64](../../../Tests/CommunityPluginRuntimeTests/tests/metadata-cache.test.js#L64)); keep through the `LinkResolver` split. |
| RUNTIME-INV-13 | Command identifiers are `<pluginId>:<commandId>` and names `<plugin name>: <command name>`. The host keys palette entries and shortcuts by them. | [plugins.js:406-413](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L406-L413) | Snapshot of `commands.changed` after `addCommand`. |
| RUNTIME-INV-14 | Leaf identifiers are `graphite-leaf-<start time base 36>-<n>`, unique per page load. The host persists them with the tab layout and must never match a leaf from an earlier start. | [workspace.js:15-18](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L15-L18) | Two runtime starts in one test produce disjoint identifier prefixes. |
| RUNTIME-INV-15 | A leaf's saved state is its view's `getState()` as JSON, sent only when at most 65,536 characters; `view.restore` parses it back. | [workspace.js:808-825](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L808-L825), [plugins.js:1322-1343](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1322-L1343) | Exists ([file-views.test.js:198](../../../Tests/CommunityPluginRuntimeTests/tests/file-views.test.js#L198)); add an oversized state that is sent as `null`. |
| RUNTIME-INV-16 | Editor changes made in one synchronous turn are sent as one `editor.apply` carrying the plugin identifier read at the first change; an answer is adopted only when no newer local change exists. | [workspace.js:365-396](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L365-L396) | Exists; add a second change made while the first is in flight. |
| RUNTIME-INV-17 | Paste and drop count as handled exactly when a listener called `preventDefault()` before the runtime's zero-delay wait ended. | [plugins.js:1086-1108](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1086-L1108) | Exists ([file-views.test.js:116](../../../Tests/CommunityPluginRuntimeTests/tests/file-views.test.js#L116)); add a listener that prevents after an `await`, to pin the chosen contract. |
| RUNTIME-INV-18 | Block copies: at most 4 MiB characters, else a "too large" placeholder; changes gathered over 60 ms; processors waited for at most 15 s; copy styles at most 3 MiB, dropping only the theme. | [reading.js:17-25](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L17-L25), [reading.js:268-277](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L268-L277), [reading.js:312-323](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L312-L323) | A processor that writes 5 MiB gets the placeholder; existing theme-size test kept. |
| RUNTIME-INV-19 | Attribute names shared with Swift copy pages: `data-graphite-listens` (values `menu`, `hover`, `press`, `drag`, `drop`), `data-graphite-task-line`, `data-graphite-source-path`; style markers `data-graphite-plugin`, `data-graphite-theme`, `data-graphite-snippet`. | [reading.js:51-58](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L51-L58), [reading.js:479](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L479), [reading.js:402](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L402), [plugins.js:608](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L608), [plugins.js:982](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L982), [plugins.js:989](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L989), [CommunityPluginReadingBlocks.swift:424](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L424) | Declared in the message schema; a test greps nothing, it asserts the attributes on a drawn block. |
| RUNTIME-INV-20 | Resource addresses are `<resourcePathPrefix><percent-encoded path components>?<mtime>`, with prefix `graphite-vault://resource/` unless the host sets another. | [foundation.js:621](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L621), [foundation.js:628](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L628), [vault.js:284-286](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L284-L286), [vault.js:603-605](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L603-L605) | `getResourcePath` of `A b/ü.png` equals the expected encoded address. |
| RUNTIME-INV-21 | `localStorage` keys are `<vault identifier>-<key>` with JSON values, in a per-vault data store. | [plugins.js:903-918](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L903-L918), [CommunityPluginHost.swift:372-373](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L372-L373) | Save then load a value under a fixed `appId`. |
| RUNTIME-INV-22 | `requestUrl` throws for status 400 and above unless `throw: false`, lower-cases header names, and makes `.json`/`.text`/`.arrayBuffer` available on the promise. | [foundation.js:565-599](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L565-L599) | Exists ([utilities.test.js:55](../../../Tests/CommunityPluginRuntimeTests/tests/utilities.test.js#L55)); add `throw: false` with 404. |
| RUNTIME-INV-23 | `runtime.receive` answers every message; unknown operations give `failure.kind = 'unknownOperation'`, handler errors `failure.kind = 'runtime'`. | [plugins.js:1541-1550](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1541-L1550) | Send an unknown operation and a handler that throws; assert both kinds. |
| RUNTIME-INV-24 | A host failure of kind `missing` carries `code = 'ENOENT'`; the adapter answers paths outside the vault or invalid as missing (`stat` null, `exists` false). | [foundation.js:25](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L25), [vault.js:98-105](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L98-L105) | `adapter.exists('../x')` is false; `adapter.read('missing.md')` rejects with `code === 'ENOENT'`. |
| RUNTIME-INV-25 | Unsupported features are reported once per plugin and feature name. | [foundation.js:95-104](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L95-L104) | Two calls produce one `plugin.unsupportedFeature`. |
| RUNTIME-INV-26 | The default API version is `1.14.4` and the host may override it at start; `requireApiVersion` compares numerically by part. | [foundation.js:13](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L13), [plugins.js:1255](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1255), [foundation.js:636-649](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L636-L649) | `requireApiVersion('1.9.10')` true, `'1.15'` false. |
| RUNTIME-INV-27 | The metadata cache reads no note over 4 MiB and no note the provider has not downloaded, at most 4 at once, and keeps no note text. | [metadata.js:16-18](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L16-L18), [metadata.js:576-580](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L576-L580) | Count concurrent `vault.read` requests in the fake host during the initial read: never above 4. |
| RUNTIME-INV-28 | The page never navigates: anchor clicks go to `workspace.openLinkText` or `workspace.openExternalLink`; `window.open` sends only `http`, `https` and `mailto`. | [reading.js:744-765](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L744-L765), [host-connection.js:32-41](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-host-connection.js#L32-L41) | Exists for anchors; add `area` and `javascript:` addresses. |

### Tests that become possible once the seams exist

- **A contract test over `community-plugin-messages.json`:** every host-to-runtime operation has a registered handler, every runtime-to-host operation is in the Swift enum, and the fake host's switch is generated, not hand-written.
- **One shared case table for `editor.apply` and `vault.write`,** run against the fake host in Node and against `CommunityPluginHost`/`CommunityPluginVaultBridge` in Swift. Cases: stale text, read-only note, closed note, `absent` on an existing file, revision mismatch.
- **Unit tests of `NoteParser`, `LinkResolver` and `VaultConfiguration` without a page,** once they no longer read `runtime.app` or the DOM.
- **`SnapshotEditor` per-path tests:** an edit through an editor of note A after a switch to B goes to A or fails, never to B.
- **`Scope` tests** for `Mod`, modifier order and parent fallback.
- **`LeafHostState` transition tests:** probe, shown by host, waiting, detached.
- **`PathWriteQueue` tests** mixing `write`, `process` and `appendBinary` on one path.
- **`coalescedNotifier` tests** with an injected scheduler, replacing timer-based waits in the suite. The harness's `settle()` sleeps 20 ms today ([runtime-harness.js:163-165](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L163-L165)), and `waitUntil` polls every 5 ms ([runtime-harness.js:148-154](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L148-L154)).

## 8. Appendix: raw metrics

### Reconnaissance figures, checked

| Metric | Reconnaissance | Checked value | Method |
| --- | --- | --- | --- |
| Files / physical / code lines | 14 / 8466 / 7287 | 14 / 8466 / 7287 (the `read_files` totals match the physical figures) | reading every file |
| Functions over 40 code lines | none | **11 functions over 40 physical lines** (table in CC-RUNTIME-01); the script's brace matcher did not recognise JavaScript class methods and object-literal methods | first and last line of each function, by reading |
| Types over 300 code lines | none | none; the largest are `NoteParser` (~297 physical, [metadata.js:30-326](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L30-L326)), `Vault` (284), `MetadataCache` (276), `SnapshotEditor` (242), `Workspace` (235) and `DataAdapter` (227) | class start and end lines |
| Files over 400 code lines | 7 | 7, the same list (`plugins.js` 1324, `interface.js` 1107, `workspace.js` 919, `vault.js` 627, `metadata.js` 626, `foundation.js` 619, `reading.js` 597) | reconnaissance |
| Commits per file | `plugins.js` 16 … `settings.js` 1 | not re-measured (no git access through the tools) | — |

### Counts made for this audit

| Count | Value | Method |
| --- | ---: | --- |
| `GraphitePluginRuntime` members assigned | 50 | `grep "runtime\.[a-zA-Z]+ = "`, duplicates removed (§3.1) |
| `runtime.app` reads | 61 (in 6 files) | `grep "runtime\.app\b"` |
| `hostBridge.send` call sites | 33 | `grep "(send\|notify)\('([a-zA-Z]+\.[a-zA-Z]+)'"`, split by verb |
| `hostBridge.notify` call sites | 37 | same grep |
| Distinct runtime-to-host operation names | 44 | same grep, deduplicated (list below) |
| Host-to-runtime handler names | 39 | reading the three handler tables (28 + 2 + 9) |
| Own-code `setTimeout` calls | 17 | `grep "setTimeout\("`, vendor lines excluded |
| Hand-written coalescing flags | 10 notifier copies + 1 save batch | `grep "Scheduled = true"` (11 matches; `isSaveScheduled` is the batch) |
| `error && error.message ? error.message : String(error)` copies | 15 | grep of the exact expression |
| Own-code lines over 160 characters | 81 | `grep "^.{161,}$"`, vendor lines excluded (per file in CC-RUNTIME-10) |
| Ad hoc fields written from other files | 9 | reading (ISP-RUNTIME-02) |
| Node tests | 85 in 12 files, 18 of them skipped when their real plugin is not built | `grep "^\s*(test\|it\|describe)\("` over `tests/*.js` |
| `App` / `Workspace` / `WorkspaceLeaf` stored fields | 21 / 20 / 15 | constructors plus assignments from other files |
| `Workspace` members | 43 | reading [workspace.js:703-937](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L703-L937) |
| `DataAdapter` methods | 28 | reading [vault.js:114-340](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L114-L340) |

### The message vocabulary in the snapshot

**Runtime to host (44):**

| Group | Operations |
| --- | --- |
| Vault | `vault.list`, `vault.listFolder`, `vault.stat`, `vault.read`, `vault.write`, `vault.createFolder`, `vault.remove`, `vault.rename`, `vault.copy` |
| Editor and workspace | `editor.apply`, `workspace.openFile`, `workspace.openLinkText`, `workspace.renameFile`, `workspace.openExternalLink`, `view.reveal`, `views.changed`, `markdown.render` |
| Panel, notices and menus | `surface.present`, `surface.dismiss`, `notice.show`, `notice.update`, `notice.hide`, `menu.show` |
| Plugin reports | `plugin.writeConflict`, `plugin.unsupportedFeature`, `plugin.failure`, `plugin.settingTabChanged`, `plugins.setEnabled` |
| Settings and services | `appearance.setConfig`, `network.request`, `secrets.set`, `settings.open`, `clipboard.readText`, `clipboard.writeText` |
| Change notices | `commands.changed`, `ribbon.changed`, `postProcessors.changed`, `codeBlocks.changed`, `fileViews.changed`, `editor.listenersChanged`, `menus.changed`, `codeBlock.changed`, `styles.changed`, `basesViews.changed` |

**Host to runtime (39):**

| Defined in | Operations |
| --- | --- |
| `plugins.js` (28) | `runtime.start`, `runtime.stop`, `plugin.load`, `plugin.unload`, `plugins.layoutReady`, `file.openInView`, `view.restore`, `vault.configuration`, `appearance.changed`, `appearance.styles`, `workspace.activeDocument`, `vault.changes`, `command.run`, `ribbon.run`, `settings.show`, `view.show`, `surface.closed`, `editor.update`, `editor.paste`, `editor.drop`, `editor.closeSuggestions`, `editor.chooseSuggestion`, `menu.file`, `menu.editor`, `notice.tap`, `menu.choose`, `menu.dismiss`, `protocol.open` |
| `bases.js` (2) | `basesView.open`, `basesView.update` |
| `reading.js` (9) | `views.saveFiles`, `view.live`, `view.unlive`, `view.attach`, `view.resize`, `view.close`, `codeBlock.render`, `codeBlock.event`, `codeBlock.release` |

### Not read

- The vendored bundles in `Vendor/` (third-party, out of scope).
- `Tests/CommunityPluginRuntimeTests/compatibility/*.js` and `tools/build-vendored-libraries.js` (build tooling).
- Seven of the twelve test files were read only through their test names and the excerpts cited above: `context-menus`, `file-views`, `metadata-cache`, `plugin-loading`, `reading-blocks`, `real-plugins`, `typing`, `utilities`. `vault.test.js` and `obsidian-conventions.test.js` were read in part.
- On the Swift side only the parts cited were read: `CommunityPluginHost.swift` 280-420 and 640-1000, `CommunityPluginTyping.swift`, `ThemeTokenResolver.swift` 120-150, `CommunityPluginReadingBlocks.swift` 395-425 and `CommunityPluginEditorChange.swift` 36-70.

Correction to the "Not read" list above: eight test files, not seven, were read only through their names and cited excerpts (the eight listed). `editor-commands.test.js`, `support/runtime-harness.js` and `support/test-vault-host.js` were read in full.

Severity tally: High 2 (SRP-RUNTIME-02, OCP-RUNTIME-01); Medium 20; Low 10. Bugs: 7 (3 traced: BUG-RUNTIME-01, 02, 03; 4 partly traced). Invariants: 28.

## 9. Since the snapshot

Delta audit of 2026-10-19 at `fff794b` (main), against `FR-01` to `FR-108`. Commits: `1f45079` (each plugin command gets its own editor), `61de461` (`Mod` shortcuts fire), `4489db2` (plugin views).

### New findings

#### LSP-RUNTIME-07 `setViewState` on the note's leaf returns without changing that leaf's view
- **Severity:** Medium
- **Rule:** `FR-30`, `FR-29`
- **Evidence:** with a note active, `getLeaf(false)` returns `markdownLeaf` ([community-plugin-runtime-workspace.js:861-864](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L861-L864)); on that leaf (kind `'mirror'`), `setViewState` creates another tab leaf, sets the state there and returns ([:609-617](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L609-L617)); the plugin's leaf keeps its `MarkdownView`, and `revealLeaf(leaf)` returns early for it ([:915](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L915)). Introduced in `4489db2`.
- **Why it matters:** in Obsidian, after `await leaf.setViewState({type})` that leaf shows the view; plugins that then read `leaf.view` act on the note's view.
- **Fix direction:** the leaf object the plugin holds becomes the one that shows the view; a Node test on `leaf.view.getViewType()`.

#### CC-RUNTIME-13 "`Mod` means Command" is decided in two functions
- **Severity:** Low
- **Rule:** `FR-10`
- **Evidence:** `Keymap.normalizedModifiers` maps `Mod` to `Meta` ([community-plugin-runtime-interface.js:173-175](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L173-L175)) and `isModifier` makes the same mapping itself ([:176-178](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L176-L178)); a registration listing both `Mod` and `Meta` becomes `"Meta,Meta"` and never matches. Introduced in `61de461`.
- **Fix direction:** one platform-modifier helper; remove duplicates when normalizing.

### State changes of earlier findings
- `SRP-RUNTIME-04`: **Worse**: `replacesCurrentTab` is a loose field not declared in the `WorkspaceLeaf` constructor ([community-plugin-runtime-workspace.js:573-588](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L573-L588), set at [:613-614](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L613-L614)).
- `CC-RUNTIME-02`: **Worse**: the `view.reveal` payload is written twice ([:664](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L664), [:920](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L920)).
- `CC-RUNTIME-10`: **Worse by two** lines over 160 characters (the same two).
