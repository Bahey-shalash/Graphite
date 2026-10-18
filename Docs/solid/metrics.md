# Metrics

Snapshot: b13dec3 (main, 2026-10-18).

Every number in the audit that describes size or frequency comes from this page. Later measurements are comparable only when they use the same method, so each table names its method. Re-run with `python3 scripts/size-report.py --list` and `python3 scripts/solid-metrics.py` on a checkout (`git worktree add <scratch> b13dec3` reproduces these exact numbers).

## Method

- **Production Swift:** `Sources/**/*.swift` and `App/GraphiteApp.swift` (321 files). **Test Swift:** `Tests/**` and `App/Tests/**` (208 files). `Vendor/` (vendored Textual and mlx-audio-swift) and the minified bundles in `Sources/GraphiteUI/Resources/CommunityPluginRuntime/Vendor/` are third-party and not measured.
- **Physical lines:** newline count. **Code lines:** physical lines left after removing line and nested block comments, the contents of string literals (single-line, multi-line and raw; interpolated code is kept) and blank lines (`strip_comments_and_strings` in `scripts/size-report.py`).
- **Declarations:** found by brace matching on the stripped text. A type's size sums its declaration and its extensions *in the same file*; a function's size covers `func`, `init`, `deinit`, `subscript` and computed properties (SwiftUI `body` included); nested functions count inside their owner; overloads with one qualified name count as the largest.
- **Patterns:** regular expressions over the stripped text, so occurrences in comments and strings are not counted. A count is an occurrence count, not a defect count: the area documents classify them.
- **JavaScript (plugin runtime):** non-blank lines not starting with `//`, `/*` or `*`.
- The area briefs used an earlier version of the same counter whose interpolation handling differs; its totals differ by at most 6 code lines per module (for example GraphiteIndex 1,930 there, 1,936 here). This page is the reference.

## Inventory by module

| Module | Files | Physical lines | Code lines |
| --- | ---: | ---: | ---: |
| `Sources/GraphiteUI` | 153 | 59,539 | 46,253 |
| `Sources/GraphiteCore` | 101 | 30,407 | 23,466 |
| `Tests/GraphiteUITests` | 66 | 15,869 | 12,886 |
| `Tests/GraphiteCoreTests` | 72 | 14,383 | 11,242 |
| `App/Tests` | 26 | 11,974 | 9,858 |
| `Sources/GraphiteApple` | 36 | 9,633 | 7,392 |
| `Tests/GraphiteAppleTests` | 25 | 7,294 | 6,126 |
| `Tests/GraphiteIndexTests` | 19 | 3,029 | 2,584 |
| `Sources/GraphiteIndex` | 7 | 2,675 | 1,936 |
| `Sources/GraphiteVoices` | 12 | 2,136 | 1,682 |
| `Sources/GraphiteBenchmarks` | 1 | 116 | 96 |
| `App` | 1 | 38 | 24 |

Own JavaScript, CSS and HTML of the plugin runtime: 14 files, 8,466 physical lines, 7,287 code lines (`Sources/GraphiteUI/Resources/CommunityPluginRuntime/` without `Vendor/`, plus `Resources/ThemeResolver/theme-probe.js` counted under PLUGIN). Its tests: `Tests/CommunityPluginRuntimeTests/`, 85 `test(`/`it(` cases.

## Inventory by audit area

Method: the reconnaissance counter (see above); files are assigned by the ordered patterns in the README's area table.

| Area | Files | Physical lines | Code lines | Functions > 40 | Types > 300 | Files > 400 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [PLUGIN](areas/plugin.md) | 27 | 6,665 | 4,968 | 6 | 1 | 3 |
| [RUNTIME](areas/runtime.md) | 14 | 8,466 | 7,287 | 0 | 0 | 7 |
| [BASES](areas/bases.md) | 26 | 10,841 | 8,679 | 29 | 3 | 8 |
| [CANVAS](areas/canvas.md) | 20 | 5,894 | 4,751 | 10 | 2 | 4 |
| [VOICE](areas/voice.md) | 53 | 10,005 | 8,116 | 19 | 4 | 3 |
| [LECTURE](areas/lecture.md) | 37 | 12,852 | 9,814 | 19 | 5 | 8 |
| [INK](areas/ink.md) | 33 | 10,875 | 8,118 | 11 | 4 | 5 |
| [MDCORE](areas/mdcore.md) | 18 | 8,923 | 6,895 | 23 | 8 | 8 |
| [EDITOR](areas/editor.md) | 19 | 10,886 | 8,062 | 13 | 8 | 5 |
| [READING](areas/reading.md) | 14 | 6,971 | 5,431 | 18 | 1 | 3 |
| [VAULT](areas/vault.md) | 34 | 9,789 | 7,303 | 13 | 2 | 4 |
| [SHELL](areas/shell.md) | 32 | 11,099 | 8,942 | 29 | 3 | 6 |
| **Total** | **327** | **113,266** | **88,366** | **190** | **41** | **64** |

## Sizes

| Item | Over first threshold | Over strong-reason threshold | Over 1,000 |
| --- | ---: | ---: | ---: |
| Functions (40 / 80 code lines) | 189 | 26 | 0 |
| Types (300 / 600) | 39 | 12 | 4 |
| Files (400 / 500) | 57 | 39 | 6 |

6,222 functions measured. A type spread over several files is larger than its per-file rows: `WorkspaceModel` is 2,695 code lines over 23 files (its main file holds 1,010), `VaultIndex` 1,206 over 7 files, `CommunityPluginHost` 1,158 over 6 files, `PDFSession` 739 over 6 files.

### Largest 20 files

| Code lines | Physical lines | File | Commits touching it |
| ---: | ---: | --- | ---: |
| 2,631 | 3,523 | [Sources/GraphiteUI/NativeMarkdownEditor.swift](../../Sources/GraphiteUI/NativeMarkdownEditor.swift) | 41 |
| 2,293 | 3,021 | [Sources/GraphiteUI/MarkdownPreview.swift](../../Sources/GraphiteUI/MarkdownPreview.swift) | 25 |
| 1,332 | 1,808 | [Sources/GraphiteUI/GraphitePDFView.swift](../../Sources/GraphiteUI/GraphitePDFView.swift) | 23 |
| 1,113 | 1,334 | [Sources/GraphiteCore/BaseEvaluator.swift](../../Sources/GraphiteCore/BaseEvaluator.swift) | 3 |
| 1,090 | 1,380 | [Sources/GraphiteUI/DrawingEditor.swift](../../Sources/GraphiteUI/DrawingEditor.swift) | 16 |
| 1,050 | 1,471 | [Sources/GraphiteUI/WorkspaceModel.swift](../../Sources/GraphiteUI/WorkspaceModel.swift) | 29 |
| 1,000 | 1,192 | [Sources/GraphiteUI/MarkdownPane.swift](../../Sources/GraphiteUI/MarkdownPane.swift) | 36 |
| 952 | 1,169 | [Sources/GraphiteUI/VaultSidebar.swift](../../Sources/GraphiteUI/VaultSidebar.swift) | 24 |
| 950 | 1,068 | [Sources/GraphiteUI/SettingsView.swift](../../Sources/GraphiteUI/SettingsView.swift) | 21 |
| 944 | 1,214 | [Sources/GraphiteCore/SearchQuery.swift](../../Sources/GraphiteCore/SearchQuery.swift) | 2 |
| 910 | 1,057 | [Sources/GraphiteCore/CodeSyntaxHighlighting.swift](../../Sources/GraphiteCore/CodeSyntaxHighlighting.swift) | 1 |
| 875 | 1,122 | [Sources/GraphiteUI/CommunityPluginHost.swift](../../Sources/GraphiteUI/CommunityPluginHost.swift) | 21 |
| 846 | 1,142 | [Sources/GraphiteCore/BaseDefinitionEditor.swift](../../Sources/GraphiteCore/BaseDefinitionEditor.swift) | 2 |
| 821 | 1,073 | [Sources/GraphiteUI/MarkdownTextStyler.swift](../../Sources/GraphiteUI/MarkdownTextStyler.swift) | 14 |
| 801 | 1,080 | [Sources/GraphiteCore/MarkdownSemantics.swift](../../Sources/GraphiteCore/MarkdownSemantics.swift) | 4 |
| 788 | 933 | [Sources/GraphiteUI/PDFPane.swift](../../Sources/GraphiteUI/PDFPane.swift) | 19 |
| 772 | 1,025 | [Sources/GraphiteUI/InkSelection.swift](../../Sources/GraphiteUI/InkSelection.swift) | 8 |
| 698 | 902 | [Sources/GraphiteApple/ReadAloudSpeech.swift](../../Sources/GraphiteApple/ReadAloudSpeech.swift) | 14 |
| 687 | 825 | [Sources/GraphiteUI/WorkspacePanes.swift](../../Sources/GraphiteUI/WorkspacePanes.swift) | 22 |
| 660 | 778 | [Sources/GraphiteUI/ReadAloudController.swift](../../Sources/GraphiteUI/ReadAloudController.swift) | 15 |

### Largest 20 types (per file)

| Code lines | Declaration | File |
| ---: | --- | --- |
| 1,947 | `NativeMarkdownEditor` | [Sources/GraphiteUI/NativeMarkdownEditor.swift](../../Sources/GraphiteUI/NativeMarkdownEditor.swift) |
| 1,616 | `Coordinator` | [Sources/GraphiteUI/NativeMarkdownEditor.swift](../../Sources/GraphiteUI/NativeMarkdownEditor.swift) |
| 1,010 | `WorkspaceModel` | [Sources/GraphiteUI/WorkspaceModel.swift](../../Sources/GraphiteUI/WorkspaceModel.swift) |
| 1,005 | `BaseEvaluator` | [Sources/GraphiteCore/BaseEvaluator.swift](../../Sources/GraphiteCore/BaseEvaluator.swift) |
| 771 | `CommunityPluginHost` | [Sources/GraphiteUI/CommunityPluginHost.swift](../../Sources/GraphiteUI/CommunityPluginHost.swift) |
| 735 | `PDFAnnotationCoordinator` | [Sources/GraphiteUI/GraphitePDFView.swift](../../Sources/GraphiteUI/GraphitePDFView.swift) |
| 734 | `CodeLineScanner` | [Sources/GraphiteCore/CodeSyntaxHighlighting.swift](../../Sources/GraphiteCore/CodeSyntaxHighlighting.swift) |
| 658 | `InkSelectionController` | [Sources/GraphiteUI/InkSelection.swift](../../Sources/GraphiteUI/InkSelection.swift) |
| 635 | `HTMLToMarkdown` | [Sources/GraphiteCore/HTMLToMarkdown.swift](../../Sources/GraphiteCore/HTMLToMarkdown.swift) |
| 617 | `ReadAloudController` | [Sources/GraphiteUI/ReadAloudController.swift](../../Sources/GraphiteUI/ReadAloudController.swift) |
| 614 | `MarkdownTextStyler` | [Sources/GraphiteUI/MarkdownTextStyler.swift](../../Sources/GraphiteUI/MarkdownTextStyler.swift) |
| 604 | `VaultIndex` | [Sources/GraphiteIndex/VaultIndex.swift](../../Sources/GraphiteIndex/VaultIndex.swift) |
| 579 | `ReadAloudDocument` | [Sources/GraphiteCore/ReadAloudDocument.swift](../../Sources/GraphiteCore/ReadAloudDocument.swift) |
| 565 | `Converter` | [Sources/GraphiteCore/HTMLToMarkdown.swift](../../Sources/GraphiteCore/HTMLToMarkdown.swift) |
| 550 | `MarkdownPane` | [Sources/GraphiteUI/MarkdownPane.swift](../../Sources/GraphiteUI/MarkdownPane.swift) |
| 544 | `MarkdownEditing` | [Sources/GraphiteCore/MarkdownEditing.swift](../../Sources/GraphiteCore/MarkdownEditing.swift) |
| 511 | `HistoryCanvasView` | [Sources/GraphiteUI/HistoryCanvasView.swift](../../Sources/GraphiteUI/HistoryCanvasView.swift) |
| 501 | `RecordingController` | [Sources/GraphiteApple/RecordingController.swift](../../Sources/GraphiteApple/RecordingController.swift) |
| 475 | `GraphiteRootView` | [Sources/GraphiteUI/GraphiteRootView.swift](../../Sources/GraphiteUI/GraphiteRootView.swift) |
| 459 | `SelectionFrameView` | [Sources/GraphiteUI/SelectionFrameView.swift](../../Sources/GraphiteUI/SelectionFrameView.swift) |

### Largest 20 functions

| Code lines | Declaration | File |
| ---: | --- | --- |
| 273 | `ReadAloudDocument.markdown` | [Sources/GraphiteCore/ReadAloudDocument.swift](../../Sources/GraphiteCore/ReadAloudDocument.swift) |
| 176 | `Converter.handleTag` | [Sources/GraphiteCore/HTMLToMarkdown.swift](../../Sources/GraphiteCore/HTMLToMarkdown.swift) |
| 172 | `GraphiteRootView.body` | [Sources/GraphiteUI/GraphiteRootView.swift](../../Sources/GraphiteUI/GraphiteRootView.swift) |
| 160 | `CodeLineScanner.scanSigil` | [Sources/GraphiteCore/CodeSyntaxHighlighting.swift](../../Sources/GraphiteCore/CodeSyntaxHighlighting.swift) |
| 149 | `ReadAloudDocument.pageText` | [Sources/GraphiteCore/ReadAloudDocument.swift](../../Sources/GraphiteCore/ReadAloudDocument.swift) |
| 127 | `MarkdownPreview.body` | [Sources/GraphiteUI/MarkdownPreview.swift](../../Sources/GraphiteUI/MarkdownPreview.swift) |
| 122 | `NoteThemeStyle.init` | [Sources/GraphiteUI/NoteThemeStyle.swift](../../Sources/GraphiteUI/NoteThemeStyle.swift) |
| 120 | `WorkspaceCommandList.commands` | [Sources/GraphiteUI/WorkspaceCommands.swift](../../Sources/GraphiteUI/WorkspaceCommands.swift) |
| 118 | `CommunityPluginHost.receiveNotification` | [Sources/GraphiteUI/CommunityPluginHost.swift](../../Sources/GraphiteUI/CommunityPluginHost.swift) |
| 115 | `MarkdownSemantics.parse` | [Sources/GraphiteCore/MarkdownSemantics.swift](../../Sources/GraphiteCore/MarkdownSemantics.swift) |
| 113 | `NoteBlocks.blocks` | [Sources/GraphiteCore/NoteBlocks.swift](../../Sources/GraphiteCore/NoteBlocks.swift) |
| 109 | `MarkdownPane.body` | [Sources/GraphiteUI/MarkdownPane.swift](../../Sources/GraphiteUI/MarkdownPane.swift) |
| 109 | `BaseEvaluator.callFunction` | [Sources/GraphiteCore/BaseEvaluator.swift](../../Sources/GraphiteCore/BaseEvaluator.swift) |
| 108 | `PDFPaneContent.body` | [Sources/GraphiteUI/PDFPane.swift](../../Sources/GraphiteUI/PDFPane.swift) |
| 105 | `ReadingBlocksView.blockView` | [Sources/GraphiteUI/MarkdownPreview.swift](../../Sources/GraphiteUI/MarkdownPreview.swift) |
| 102 | `DrawingsSettingsPage.body` | [Sources/GraphiteUI/SettingsView.swift](../../Sources/GraphiteUI/SettingsView.swift) |
| 101 | `NotePreviewDocument.blocks` | [Sources/GraphiteCore/NotePreviewDocument.swift](../../Sources/GraphiteCore/NotePreviewDocument.swift) |
| 100 | `MarkdownStyleScanner.inlineSpans` | [Sources/GraphiteCore/MarkdownStyleScanner.swift](../../Sources/GraphiteCore/MarkdownStyleScanner.swift) |
| 96 | `ThemeProbeReading.tokens` | [Sources/GraphiteCore/VaultThemeTokens.swift](../../Sources/GraphiteCore/VaultThemeTokens.swift) |
| 95 | `LivePreviewBlockScanner.blocks` | [Sources/GraphiteCore/LivePreviewBlocks.swift](../../Sources/GraphiteCore/LivePreviewBlocks.swift) |

## Pattern counts

| Pattern (production Swift) | Count | Regular expression |
| --- | ---: | --- |
| try? | 628 | `\btry\?` |
| try! | 2 | `\btry!` |
| empty catch block | 5 | `catch\s*(\w+\s*)?\{\s*\}` |
| sleep (Task.sleep, sleep, usleep) | 51 | `Task\.sleep\|\bsleep\(\|usleep\(\|Thread\.sleep` |
| DispatchQueue asyncAfter | 10 | `asyncAfter\(` |
| uses of .shared | 70 | `\.shared\b` |
| static let/var shared declarations | 11 | `static\s+(let\|var)\s+shared\b` |
| static var | 77 | `\bstatic\s+var\b` |
| nonisolated(unsafe) | 4 | `nonisolated\(unsafe\)` |
| @unchecked Sendable | 20 | `@unchecked\s+Sendable` |
| MainActor.assumeIsolated | 41 | `assumeIsolated` |
| Date() and Date.now | 22 | `\bDate\(\)\|\bDate\.now\b` |
| other clock reads | 31 | `CFAbsoluteTimeGetCurrent\|systemUptime\|DispatchTime\.now\|ContinuousClock\|SuspendingClock` |
| UserDefaults | 56 | `\bUserDefaults\b` |
| FileManager.default | 190 | `FileManager\.default` |
| URLSession | 17 | `\bURLSession\b` |
| NotificationCenter.default | 53 | `NotificationCenter\.default` |
| default: in a switch | 263 | `^\s*default\s*:` |
| [String: Any] | 132 | `\[String\s*:\s*Any\??\]` |
| unstructured Task { } and Task.detached | 429 | `\bTask\s*(\(priority[^)]*\))?\s*\{\|Task\.detached` |
| DispatchQueue.main | 38 | `DispatchQueue\.main` |
| fatalError / preconditionFailure | 11 | `fatalError\(\|preconditionFailure\(` |
| #if os(...) | 76 | `#if\s+os\(\|#elseif\s+os\(` |

Notes: `try?` is the largest single error-handling pattern (628, of which CommunityPluginHost.swift 37, RecordingController.swift 21, WorkspaceModel.swift 20, MarkdownPreview.swift 18). `[String: Any]` is concentrated in the plugin bridge (CommunityPluginHost.swift 46, CommunityPluginVaultBridge.swift 14). `default:` is concentrated in BaseEvaluator.swift (41) and SearchQuery.swift (13); many switch over external values (YAML, JSON, tokens), which the area documents separate from switches over the app's own enums. TODO/FIXME: 0 in code, 3 in comments.

## Change hotspots

Method: `git log b13dec3 --format= --name-only | sort | uniq -c | sort -rn` over all 242 commits.

| Commits | File |
| ---: | --- |
| 112 | `Docs/Coverage.md` |
| 97 | `Docs/Architecture.md` |
| 41 | `Sources/GraphiteUI/NativeMarkdownEditor.swift` |
| 36 | `Sources/GraphiteUI/MarkdownPane.swift` |
| 29 | `Sources/GraphiteUI/WorkspaceModel.swift` |
| 28 | `Sources/GraphiteUI/GraphiteRootView.swift` |
| 25 | `Sources/GraphiteUI/MarkdownPreview.swift` |
| 24 | `Sources/GraphiteUI/VaultSidebar.swift` |
| 23 | `Sources/GraphiteUI/GraphitePDFView.swift` |
| 22 | `Sources/GraphiteUI/WorkspacePanes.swift` |
| 21 | `Sources/GraphiteUI/SettingsView.swift` |
| 21 | `Sources/GraphiteUI/CommunityPluginHost.swift` |
| 19 | `Sources/GraphiteUI/PDFPane.swift` |
| 19 | `Graphite.xcodeproj/project.pbxproj` |
| 17 | `Sources/GraphiteUI/LivePreviewWidgets.swift` |
| 16 | `Sources/GraphiteUI/HistoryCanvasView.swift` |
| 16 | `Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js` |
| 16 | `Sources/GraphiteUI/DrawingEditor.swift` |
| 15 | `Sources/GraphiteUI/ReadAloudController.swift` |
| 15 | `App/Tests/PencilToolsTests.swift` |
| 15 | `Sources/GraphiteUI/PencilToolbox.swift` |
| 14 | `Sources/GraphiteUI/MarkdownTextStyler.swift` |
| 14 | `Sources/GraphiteApple/ReadAloudSpeech.swift` |
| 14 | `Sources/GraphiteUI/GraphitePreferences.swift` |
| 14 | `App/Tests/PicturesAndPaperTests.swift` |
| 13 | `Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js` |
| 12 | `Sources/GraphiteUI/PDFSession.swift` |
| 11 | `Sources/GraphiteUI/WorkspaceTabs.swift` |
| 11 | `Sources/GraphiteUI/SelectionFrameView.swift` |
| 10 | `Sources/GraphiteApple/PDFPageManager.swift` |

The two documentation files change in 112 and 97 of 242 commits because every feature commit updates them. Among sources, the editor, note pane, workspace model and root view change in 12–17% of all commits: a new feature in Graphite edits them, which is where open/closed fails (see [open-closed](principles/open-closed.md)).

## Comments

Method: a comment-only line is a non-blank line that is blank after removing comments (strings kept).

- Production Swift: 14,959 comment-only lines against 80,841 code lines (0.185 per code line). Largest: NativeMarkdownEditor.swift 630, MarkdownPreview.swift 500, WorkspaceModel.swift 324, GraphitePDFView.swift 317, BaseDefinitionEditor.swift 205.
- History narration: 35 comment lines carry a calendar date (`grep -rnE '//.*20[0-9]{2}-[0-9]{2}-[0-9]{2}' Sources App/GraphiteApp.swift`); 16 of them record an incident or measurement (`measured|reported|seen|crashed|found|recorded` before the date), the rest are format examples such as `2026-02-30`. 14 lines name the owner or the owner's iPad (`grep -rnE "//.*\b(owner's iPad|reported by the owner|the owner)" Sources`). 5 lines say "used to". The area documents classify the remaining comments.

## Dependency graph

Method: `Package.swift` target dependencies and `import` lines per module.

```
GraphiteCore      Foundation, CoreGraphics, Yams, Markdown (swift-markdown), CryptoKit, zlib, Synchronization
  ^
GraphiteIndex     GraphiteCore, GRDB
GraphiteApple     GraphiteCore + UIKit, AppKit, PDFKit, PencilKit, AVFoundation, ImageIO, Vision, JavaScriptCore, MetricKit, Security
GraphiteVoices    GraphiteCore, GraphiteApple, MLXAudioTTS (Vendor/mlx-audio-swift)
  ^
GraphiteUI        GraphiteCore, GraphiteIndex, GraphiteApple, GraphiteVoices, Textual (Vendor/textual) + SwiftUI, UIKit, AppKit, WebKit, MapKit, PDFKit, PencilKit
  ^
App (Xcode target) GraphiteUI
GraphiteBenchmarks GraphiteCore, GraphiteIndex
```

No module imports a module above it and SwiftPM forbids cycles. GraphiteCore imports no UI framework. GraphiteUI is one module of 153 files and 46,253 code lines (57% of production code) holding every feature's views, view models and sessions; features cannot be compiled, tested or owned apart. Details and the target layout: [architecture](cross-cutting/architecture.md).

## Tests

| Test module | Sleeps | UserDefaults.standard | XCTest functions |
| --- | ---: | ---: | ---: |
| `App/Tests` | 173 | 75 | 214 |
| `Tests/GraphiteAppleTests` | 10 | 0 | 272 |
| `Tests/GraphiteCoreTests` | 0 | 0 | 1043 |
| `Tests/GraphiteIndexTests` | 2 | 0 | 140 |
| `Tests/GraphiteUITests` | 76 | 26 | 641 |


Method: sleeps and `UserDefaults.standard` are counted on raw test text (including comments); XCTest functions are `func test…(` declarations. No test uses Swift Testing (`@Test`: 0). No CI configuration exists in the repository. 20 test files are named after an audit round or fix (`*FixTests`, `*RegressionTests`). Test Swift: 208 files, 42,696 code lines.
