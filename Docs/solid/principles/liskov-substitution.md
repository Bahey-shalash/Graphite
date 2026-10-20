# Liskov substitution (LSP)

Snapshot: b13dec3 (main, 2026-10-18).

Scope: the 58 `LSP-*` findings of the twelve area audits and the cross-cutting audit ([findings-index.md](../findings-index.md): 8 High, 30 Medium, 20 Low). For Graphite, "substitution" covers five kinds of interchangeable code. Each must keep one contract:

- **Runtime substitutes:** conformers of one protocol (production adapters, fakes, stubs).
- **Compile-time substitutes:** the iPad (UIKit) and Mac (AppKit) variants of one type name behind `#if canImport`.
- **Parallel implementations of one rule:** two functions that answer the same question about the same input.
- **Test doubles across languages:** the Node test host standing in for the Swift bridge.
- **Identity and equality:** `Identifiable.id` and `==` standing in for "the same thing".

Every claim below cites findings by ID. Every file:line link was read for this document. `defects.md` does not exist in the snapshot, so defect severities are the auditors' own.

## 1. Verdict by area

| Area | Area verdict (L) | High | Medium | Low | Total | Reason, with numbers |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| [SHELL](../areas/shell.md) | Mixed | 0 | 2 | 2 | 4 | Failed reads show as empty lists at 5 sites in 3 files. "Read this note aloud" has 2 implementations that disagree about folded text. `highlightedExcerpt` returns plain text on the Mac. |
| [EDITOR](../areas/editor.md) | Weak | 1 | 3 | 2 | 6 | The Mac editor serves none of 6 session duties the iPad editor serves (4 Mac defects). Suspend, undo fallback and image conversion differ per platform. 1 styler mode exists only for a test. |
| [READING](../areas/reading.md) | Weak | 1 | 3 | 2 | 6 | Heading and callout fold keys come from rewritten display text in reading view and from the source elsewhere (2 defects). 2 link resolvers and 2 Wikilink label rules disagree (1 defect each). |
| [MDCORE](../areas/mdcore.md) | Weak | 1 | 0 | 2 | 3 | Fence (7), list (7), heading (5), display-math (5), thematic-break (5), indentation (5) and code-span (4) rules each have several implementations. They give different answers for the same line. 4 of the area's 6 defects follow from this. |
| [VAULT](../areas/vault.md) | Mostly strong | 1 | 3 | 0 | 4 | 2 implementations of "how many files share this name" disagree on non-ASCII capitals (BUG-VAULT-01). The conflict-version fake differs from production in 4 places. 4 types have an identity that differs from their equality. |
| [BASES](../areas/bases.md) | Weak | 1 | 2 | 0 | 3 | The in-memory and index record providers disagree on 4 rules. 21 Core test call sites run only the in-memory one, which production never uses. A failed lookup answers `nil`. |
| [CANVAS](../areas/canvas.md) | Mostly strong | 0 | 2 | 1 | 3 | Byte-exact undo holds. The Mac board host registers 3 of the UIKit host's 7 gestures (no tap, BUG-CANVAS-03). An unreadable canvas reports 0 links. |
| [INK](../areas/ink.md) | Mostly strong | 0 | 2 | 2 | 4 | `HistoryCanvasView` subclasses honour the base. 3 drawing-format readers encode failure 3 ways. 1 stub conformer has 5 no-op members. Hold-to-shape and lift recognise one stroke from 2 different inputs (BUG-INK-02). |
| [LECTURE](../areas/lecture.md) | Mixed | 0 | 5 | 0 | 5 | 2 signature detectors apply different rules. The Mac `GraphitePDFView` ignores 10 of its 15 inputs. Bookmarks are recognised by the display prefix `"Page "`. Tests drive `RecordingController` through states production never reaches. |
| [VOICE](../areas/voice.md) | Weak | 1 | 2 | 3 | 6 | The 2 `ReadAloudSpeaking` adapters disagree on 7 contract points, which causes 3 defects. 10 of 16 requirements have defaults, and these defaults drop request fields. 4 functions named `stop` have 4 scopes (2 defects). |
| [PLUGIN](../areas/plugin.md) | Mixed | 1 | 2 | 1 | 4 | The Node test host differs from the Swift bridge in 7 behaviours and hides BUG-PLUGIN-03. 7 reads turn a failure into an empty result, one of which erases secrets (BUG-PLUGIN-05). |
| [RUNTIME](../areas/runtime.md) | Mixed | 0 | 2 | 4 | 6 | The Node host accepts editor changes production refuses. Tests pin a `vault.changes` shape production never sends. 2 config readers and 2 placement functions disagree. The ES5 class shim keeps `instanceof` exact. |
| [ARCH](../cross-cutting/architecture.md) | Mixed | 1 | 2 | 1 | 4 | 2 media vocabularies classify 5 extensions differently (BUG-ARCH-01). 4 link resolvers in different modules disagree (BUG-ARCH-05). The conflict-version fake is safer than production. PDF sessions fall back to a writer without the vault's presenter. |
| **All** | | **8** | **30** | **20** | **58** | 5 areas Weak, 5 Mixed, 3 Mostly strong. |

**App-wide verdict: Weak.** Substitution holds where Graphite has one owner and a narrow port: `MarkdownStyledTextView`, `VideoCaptureSource`, the canvas splice engine and the bridge's typed failure answers. It fails wherever one behaviour exists twice: across platforms, across Core and UI, across Swift and the Node test host. No interface in the snapshot has a shared contract test suite (grep `[Cc]ontract` over `Tests/**` and `App/Tests/**` finds only comments). So the copies drift apart unnoticed, and the findings trace 29 distinct user-visible defects to this drift (section 2).

## 2. Systemic patterns across the whole app

Each of the 58 findings belongs to exactly one of six patterns. The patterns are ordered by cost: first the number of distinct defects the findings trace to them, then, on a tie, whether user data is lost.

| # | Pattern | Findings | Areas | Defects traced |
| ---: | --- | ---: | ---: | ---: |
| 2.1 | One rule, several implementations | 19 | 11 | 15 |
| 2.2 | Platform variants under one name honour different contracts | 8 | 5 | 5 |
| 2.3 | A failure is returned as an empty result or as success | 8 | 7 | 3 (2 lose user data) |
| 2.4 | Conformers of one protocol honour different contracts | 8 | 7 | 3 |
| 2.5 | Test doubles and test-only paths differ from production | 8 | 8 | 2 hidden from the suite |
| 2.6 | Identity and equality do not mean "the same thing" | 7 | 5 | 1 |

### 2.1 One rule, several implementations

**What it is.** Two or more functions answer the same question about the same input: whether a line is a fence, which file a link names, whether a file is audio, which key a folded heading gets. They are written separately, and they answer differently at the edges. Every caller assumes "the" answer.

**Where it occurs (19 findings, 11 areas).**

| Rule | Implementations | Findings | Defects |
| --- | ---: | --- | --- |
| Markdown line syntax: fence, list, heading, display math, thematic break, indentation, code span | 7 / 7 / 5 / 5 / 5 / 5 / 4 | `LSP-MDCORE-01` | BUG-MDCORE-02, -03, -04 |
| Private-use marker protection | 2 | `LSP-MDCORE-02` | BUG-MDCORE-06 |
| Link resolution | 7 entry points (section 7) | `LSP-ARCH-02`, `LSP-READING-03`, `LSP-VAULT-03` | BUG-ARCH-05 (= BUG-READING-03) |
| Media classification | 3 lists | `LSP-ARCH-01` | BUG-ARCH-01 |
| Heading fold key | 3 (1 Core, 2 reading view) | `LSP-READING-01` | BUG-READING-01 |
| Wikilink display text | 2 | `LSP-READING-04` | BUG-READING-05 |
| Files sharing a name | 2 | `LSP-VAULT-01` | BUG-VAULT-01 |
| Image import format | 3 | `LSP-EDITOR-05` | — |
| Shape recognition of one stroke | 2 inputs | `LSP-INK-03` | BUG-INK-02 |
| History refusal for `PencilDrawingChange` | 2 owners | `LSP-INK-04` | — |
| Digital-signature detection | 2 | `LSP-LECTURE-01` | — |
| "Stop reading" | 4 scopes | `LSP-VOICE-03` | BUG-VOICE-01, -02 |
| Word at a playback time | 2 | `LSP-VOICE-05` | — |
| Read a note aloud | 2 entry points | `LSP-SHELL-01` | BUG-SHELL-01 |
| Vault configuration value | 2 readers | `LSP-RUNTIME-03` | BUG-RUNTIME-07 |
| Leaf placement | 2 | `LSP-RUNTIME-04` | — |
| Base view option keys (reader aliases vs editor setter) | 2 vocabularies | `LSP-BASES-03` | BUG-BASES-01 |

**Evidence.**
- *Media classification.* `DocumentKind` lists six media extensions ([VaultPath.swift:168](../../../Sources/GraphiteCore/VaultPath.swift#L168)). `MediaFileKind` lists eleven ([MarkdownPreview.swift:232-234](../../../Sources/GraphiteUI/MarkdownPreview.swift#L232-L234)). The reading view asks `MediaFileKind` first and `DocumentKind` second, in one function ([MarkdownPreview.swift:448-450](../../../Sources/GraphiteUI/MarkdownPreview.swift#L448-L450)). Recording recovery keeps a third list ([RecordingRecovery.swift:50](../../../Sources/GraphiteCore/RecordingRecovery.swift#L50)).
- *Heading fold key.* The reading view builds `"h\(level)|" + "#"×level + " " + text` from the prepared heading text, twice ([MarkdownPreview.swift:1015-1018](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1015-L1018), [MarkdownPreview.swift:1367-1371](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1367-L1371)). The comment there claims "The editor's key: the heading line as written". The editor's key is the trimmed source line ([NoteFolding.swift:62](../../../Sources/GraphiteCore/NoteFolding.swift#L62)).
- *Link resolution.* The workspace refuses folders ([WorkspaceModel.swift:656-659](../../../Sources/GraphiteUI/WorkspaceModel.swift#L656-L659)). The reading builder accepts any existing path ([MarkdownPreview.swift:488-491](../../../Sources/GraphiteUI/MarkdownPreview.swift#L488-L491)). The plugin runtime picks the shortest of several matches ([community-plugin-runtime-metadata.js:468-470](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L468-L470)), where the workspace refuses to choose ([WorkspaceModel.swift:661-662](../../../Sources/GraphiteUI/WorkspaceModel.swift#L661-L662)).
- *Files sharing a name.* `fileCount(named:)` compares `folded_name` ([VaultIndex.swift:419-422](../../../Sources/GraphiteIndex/VaultIndex.swift#L419-L422)). `fileCount(named:excluding:)` compares `name_key = ? COLLATE NOCASE` ([VaultFileOperations.swift:392](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L392)). Its doc comment claims both compare alike ([VaultFileOperations.swift:387-388](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L387-L388)).
- *Base view option keys.* The reader accepts `defaultZoom` or `zoom` ([BaseDefinition.swift:495](../../../Sources/GraphiteCore/BaseDefinition.swift#L495)). The setter writes only the key it is given ([BaseDefinitionEditor.swift:293-299](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L293-L299)).
- *Read a note aloud.* The `graphite://read` path calls `readMarkdown(session.text, path:)` with no hidden ranges ([WorkspaceDeepLinks.swift:46](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L46)).

**Cost.**
- 15 distinct defects, the most of any pattern.
- 5 of the 8 High LSP findings: `LSP-MDCORE-01`, `LSP-ARCH-01`, `LSP-READING-01`, `LSP-VAULT-01`, and `LSP-BASES-01` through its link rules.
- Every fix to an Obsidian rule has to be made up to seven times.
- Only one pair of copies is guarded by a parity test (`NoteFolding.isListItem` against `MarkdownEditing.listLine`, [NoteFoldingTests.swift:75-81](../../../Tests/GraphiteCoreTests/NoteFoldingTests.swift#L75-L81)). One more pair, the graph resolver against the SQL resolver, is kept equal by a test hook (`LSP-VAULT-03`).

**Shared fix direction.**
- Each rule gets one owner in Core, named after the question it answers: `MarkdownLineSyntax` (`LSP-MDCORE-01`), `LinkResolutionPolicy` over a candidate-lookup port (`LSP-ARCH-02`), `DocumentKind` with `.media(.audio)` / `.media(.video)` (`LSP-ARCH-01`), `NoteFolding.headingKey(rawLine:occurrence:)` (`LSP-READING-01`), `LinkDisplayText` (`LSP-READING-04`), `BaseViewOptionKey` (`LSP-BASES-03`).
- Every other copy is deleted, or it calls the owner.
- A hand-written performance mirror stays only with a corpus parity test, as `NoteFoldingTests` does (MDCORE "What to keep" rows 7 and 8).

### 2.2 Platform variants under one name honour different contracts

**What it is.** One SwiftUI type name has a UIKit body and an AppKit body behind `#if canImport`. Callers write one call for both platforms. The Mac body silently drops inputs, gestures and duties the iPad body serves.

**Where it occurs (8 findings, 5 areas).**
- EDITOR: `LSP-EDITOR-01` (6 session duties), `LSP-EDITOR-02` (suspend and dismantle), `LSP-EDITOR-03` (undo fallback and scroll restore), `LSP-EDITOR-06` (cursor placed).
- LECTURE: `LSP-LECTURE-02` (10 of 15 inputs ignored).
- CANVAS: `LSP-CANVAS-02` (3 of 7 gestures).
- SHELL: `LSP-SHELL-03` (no search highlight on the Mac).
- VOICE: `LSP-VOICE-06` (highlight colour fixed at creation on the Mac).

**Evidence.**
- *Editor session duties.* Every line that serves `startsEditingWhenShown`, `findRequest`, `takeEditingStartLocation`, `recordEditorPlace`, `isTyping` or `hasPlacedCursor` sits between lines 991 and 1699 of `NativeMarkdownEditor.swift`, the iPad coordinator (grep, 12 lines). The Mac initializer accepts `readAloudHooks` and never stores it ([NativeMarkdownEditor.swift:2705-2723](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2705-L2723)). The Mac `update` handles insertions, external text and jumps only ([NativeMarkdownEditor.swift:2792-2838](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2792-L2838)).
- *Editor undo.* On the Mac, `replaceText` falls back to `textView.string = newText` when `shouldChangeText` refuses ([NativeMarkdownEditor.swift:3222-3225](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L3222-L3225)). Its own doc comment says setting the whole text breaks undo ([NativeMarkdownEditor.swift:3207-3208](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L3207-L3208)).
- *PDF view.* The Mac `GraphitePDFView` declares 15 inputs ([GraphitePDFView.swift:1715-1735](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1715-L1735)). Five of them carry the comment "accepted so both platforms share one call". `makeNSView` and `updateNSView` read `session`, `initialPageIndex` and the three reading values only ([GraphitePDFView.swift:1744-1764](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1744-L1764)).
- *Canvas board.* The UIKit host installs pan, pinch, drag, tap, double tap and long press ([CanvasBoardHost.swift:75-92](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L75-L92)). The Mac host installs drag, magnify and double tap ([CanvasBoardHost.swift:212-230](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L212-L230)).
- *Search highlight.* `highlightedExcerpt` adds attributes only under `#if canImport(UIKit)` ([VaultSidebar.swift:1158-1167](../../../Sources/GraphiteUI/VaultSidebar.swift#L1158-L1167)).

**Cost.**
- 5 Mac defects: BUG-EDITOR-01 to -04 and BUG-CANVAS-03.
- On the Mac, three hidden notes keep their block views and a 64 MB pool each (`LSP-EDITOR-02`).
- A caller cannot tell from the type which inputs work. "Undo takes it back as one step" depends on the platform (`LSP-EDITOR-03`).

**Shared fix direction.**
- Shared behaviour lives once, in platform-neutral code, with thin platform hooks. The EDITOR area does this already for the context menu model (section 4).
- A representable accepts only inputs it honours. Optional platform parts are optional sub-values of one configuration value (`PDFViewConfiguration`, `LSP-LECTURE-02`).
- One contract test runs against both platform bodies: in package tests on macOS, and in hosted tests on iPad.

### 2.3 A failure is returned as an empty result or as success

**What it is.** A read that fails returns `[]`, `[:]`, `nil` or a default, so the caller cannot tell "nothing there" from "could not look". The same goes for a write or an action that reports success without checking that the work happened.

**Where it occurs (8 findings, 7 areas).**
- `LSP-SHELL-02`: File Recovery and the quick switcher.
- `LSP-CANVAS-01`: an unreadable canvas has zero links.
- `LSP-LECTURE-05`: recording recovery listings.
- `LSP-PLUGIN-02`: 7 reads.
- `LSP-PLUGIN-03`: a non-object runtime answer counts as success.
- `LSP-BASES-02`: a failed lookup answers "missing".
- `LSP-INK-01`: format readers turn a parse error into `nil`.
- `LSP-RUNTIME-06`: `savedCount` counts attempts.

**Evidence.**
- *File Recovery.* `(try? fileRecovery.recoverableNotes()) ?? []` ([FileRecoverySheet.swift:60](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L60)), the same for snapshots ([FileRecoverySheet.swift:101](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L101)) and for snapshot text ([FileRecoverySheet.swift:145](../../../Sources/GraphiteUI/FileRecoverySheet.swift#L145)).
- *Canvas links.* `if let file = try? CanvasFile(...)` falls through to empty semantics ([CanvasLinks.swift:76-86](../../../Sources/GraphiteCore/CanvasLinks.swift#L76-L86)).
- *Recording recovery.* Folder listings return `[]` on error ([RecordingRecovery.swift:101](../../../Sources/GraphiteCore/RecordingRecovery.swift#L101), [RecordingRecovery.swift:122](../../../Sources/GraphiteCore/RecordingRecovery.swift#L122)).
- *Plugin secrets.* `secrets()` returns `[:]` for every keychain status but success ([CommunityPluginSecretStore.swift:47-48](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L47-L48)). `setSecret` writes on top of that result ([CommunityPluginSecretStore.swift:53-58](../../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L53-L58)).
- *Base lookups.* The index provider records the error in a side channel and returns `nil` ([BaseRecordQueries.swift:269-274](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L269-L274)).
- *Drawing metadata.* The PNG/SVG metadata reader returns `try? readMetadata(...)` ([DrawingFileService.swift:88-89](../../../Sources/GraphiteApple/DrawingFileService.swift#L88-L89)).
- Production Swift holds 628 `try?` ([metrics.md](../metrics.md), pattern counts).

**Cost.**
- 3 defects: BUG-SHELL-05 (File Recovery says "No Snapshots Yet"), BUG-CANVAS-05 (a rename leaves a canvas pointing at the old path, unreported), BUG-PLUGIN-05 (a failed keychain read erases every other plugin secret of the vault).
- Two near-misses in `LSP-PLUGIN-02`. A failed folder listing lets `rmdir(path, false)` delete a non-empty folder permanently (item 6). A failed `app.json` read hands plugins Obsidian's defaults, which they write back.
- The same habit appears in the clean-code findings `CC-ARCH-02` (20 of 63 sampled `try?` hide user-relevant failures), `CC-VAULT-01`, `CC-READING-04` and `CC-EDITOR-09`.

**Shared fix direction.**
- Reads throw a typed error with a distinct `notFound` case where absence is legitimate.
- Views show a failure state distinct from the empty state.
- A success answer is computed from what happened (a returned outcome), never from "a file exists at the destination" or from the number of attempts.
- Side channels such as `throwIfLookupFailed()` become `throws` on the requirement (`LSP-BASES-02`).

### 2.4 Conformers of one protocol honour different contracts

**What it is.** Two production types conform to one protocol, or one value type has two shapes, and they behave differently for the same call. Three forms appear:

- Defaults in a protocol extension drop request fields.
- A conformer stubs requirements as no-ops.
- A default argument silently swaps in a weaker implementation.

**Where it occurs (8 findings, 7 areas).**
- VOICE: `LSP-VOICE-01` (7 contract points), `LSP-VOICE-02` (defaults drop fields), `LSP-VOICE-04` (word-timing memory keyed on the wrong voice).
- BASES: `LSP-BASES-01` (in-memory against index provider).
- INK: `LSP-INK-02` (`SelectedPicturesContent` with 5 no-ops).
- PLUGIN: `LSP-PLUGIN-04` (one "code block" type serves blocks, sections and views).
- RUNTIME: `LSP-RUNTIME-05` (`ObjectValue.entries` is an object or an array of pairs).
- ARCH: `LSP-ARCH-04` (`?? AtomicFileWriter()` without the vault's presenter).
- The suspend contract of `RetainableMarkdownEditor` is a further case. It is filed under 2.2 as `LSP-EDITOR-02`.

**Evidence.**
- *Read Aloud defaults.* The protocol has 16 requirements, and 10 of them have defaults ([ReadAloudSpeech.swift:101-153](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L101-L153)). The default `speak(_ utterance:)` forwards without the phonetic ranges and passage. The default six-parameter `speak` drops `leadingPauseSeconds` and `usesSystemSettings` ([ReadAloudSpeech.swift:135-144](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L135-L144)).
- *Read Aloud speed and voice.* The Apple adapter maps 0.5–3× onto the synthesizer rate ([ReadAloudSpeech.swift:311-316](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L311-L316)). The neural player clamps to 0.5–1.5× ([RenderedPassagePlayer.swift:39](../../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L39)). The neural adapter ignores `voiceIdentifier` and reads `library.selectedVoice` ([NeuralReadAloudSpeech.swift:71-77](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L71-L77)). It observes interruptions only, not route changes ([NeuralReadAloudSpeech.swift:45-51](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L45-L51)).
- *Base record providers.* The in-memory provider matches a rooted partial path as a suffix ([BaseFileRecord.swift:270-276](../../../Sources/GraphiteCore/BaseFileRecord.swift#L270-L276)). The index matches it from the root only ([VaultIndex.swift:385-387](../../../Sources/GraphiteIndex/VaultIndex.swift#L385-L387)). The index rejects a target containing `:` ([VaultIndex.swift:378](../../../Sources/GraphiteIndex/VaultIndex.swift#L378)); the in-memory provider looks it up. The in-memory provider's comment claims it follows the index's rules ([BaseFileRecord.swift:243-245](../../../Sources/GraphiteCore/BaseFileRecord.swift#L243-L245)). A `nil` provider silently becomes the in-memory one ([BaseEvaluator.swift:78-83](../../../Sources/GraphiteCore/BaseEvaluator.swift#L78-L83)).

**Cost.**
- 3 defects: BUG-VOICE-04 (High Quality plays at 1.5× while the control shows more), BUG-VOICE-05 (no working speed control under VoiceOver), BUG-VOICE-08 (unplugging headphones does not pause).
- After one unaligned neural passage, every later passage starts with a whole-passage highlight (`LSP-VOICE-04`).
- An editing call through `SelectedPicturesContent` is silently lost (`LSP-INK-02`).
- A plugin's Bases view reading `value.entries.status` gets `undefined` (`LSP-RUNTIME-05`).

**Shared fix direction.**
- State each protocol's contract once: ranges, events, failures, which request fields must be honoured.
- One required entry point per operation, with no forwarding overloads in extensions (`LSP-VOICE-02`).
- Capabilities an adapter lacks are values it reports (`supportedSpeedRange`, word timing per request), never silent defaults.
- A conformer that would stub a mutating requirement means the protocol is too wide: split it (`ISP-INK-01`, `ISP-VOICE-01`).
- No default argument picks a different implementation (`DIP-BASES-03`, `LSP-ARCH-04`).

### 2.5 Test doubles and test-only paths differ from production

**What it is.** A fake, a cross-language test host, a test-only entry point or a test payload makes the system look safer or simpler than it is. Tests then prove behaviour production does not have.

**Where it occurs (8 findings, 8 areas, plus cross-references).**
- PLUGIN: `LSP-PLUGIN-01` (the Node host differs from the bridge in 7 behaviours).
- RUNTIME: `LSP-RUNTIME-01` (the Node host accepts stale editor changes), `LSP-RUNTIME-02` (tests pin a `vault.changes` shape production never sends).
- VAULT: `LSP-VAULT-02` (the conflict-version fake, 4 divergences).
- ARCH: `LSP-ARCH-03` (the same fake, compiled into 2 targets).
- LECTURE: `LSP-LECTURE-03` (`adoptRecording` sets states production never reaches).
- EDITOR: `LSP-EDITOR-04` (a styler mode used only by a test that describes the Mac wrongly).
- MDCORE: `LSP-MDCORE-03` (tests pin 2 wrappers production never calls).
- Cross-references from other patterns: `LSP-BASES-01` (21 Core test sites against the in-memory provider), `LSP-VOICE-02` (6 private fakes inherit the dropping defaults), `LSP-LECTURE-01` (tests pin a detector production never calls), `LSP-VOICE-05` (tests pin the unused timing model).

**Evidence.**
- *Rename onto a taken name.* The Node host refuses it with `exists` ([test-vault-host.js:94](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L94), [test-vault-host.js:107-109](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L107-L109)). Production answers success whenever any file exists at the destination ([CommunityPluginHost.swift:922-933](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L922-L933)). The bridge's doc comment requires that the two "keep the same operations, answers and failure kinds" ([CommunityPluginVaultBridge.swift:10-12](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L10-L12)).
- *Editor changes.* The Node host accepts any change whose snapshot identifier matches and never compares text ([test-vault-host.js:223-228](../../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L223-L228)).
- *Conflict versions.* The fake treats a missing coordination outcome as success (`try outcome?.get()`, [TestConflictVersionStore.swift:87](../../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L87)). Production throws ([FileVersionConflicts.swift:167](../../../Sources/GraphiteApple/FileVersionConflicts.swift#L167)). The fake's `removeVersions` does no coordinated write ([TestConflictVersionStore.swift:98-100](../../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L98-L100)).
- *Styler mode.* `drawsConcealedReplacements` is set to `false` only in [UiStylingFixTests.swift:43](../../../Tests/GraphiteUITests/UiStylingFixTests.swift#L43). It still guards 6 production branches in `MarkdownTextStyler.swift` (grep).
- *Private fakes.* Six test files each declare their own private `ReadAloudSpeaking` fake (grep `: ReadAloudSpeaking`), for example [ReadAloudControllerTests.swift:10](../../../Tests/GraphiteUITests/ReadAloudControllerTests.swift#L10) and [ReadAloudSessionTests.swift:7](../../../Tests/GraphiteAppleTests/ReadAloudSessionTests.swift#L7).

**Cost.**
- 2 defects pass the suite because of the double: BUG-PLUGIN-03 (a plugin rename onto an existing name is reported as done) and BUG-RUNTIME-01 (an asynchronous plugin edit lands in the note the person switched to).
- The hosted shape test feeds both recognisers the same coordinates, which assumes zoom 1 and so misses BUG-INK-02 (`LSP-INK-03`).
- The 84 Node runtime tests run against a host that is safer than production for rename and less safe for trash (`LSP-PLUGIN-01`).
- `RULES.md` forbids exactly this ("a test adapter must not make an operation appear safer than production"), as `LSP-VAULT-02` and `LSP-RUNTIME-01` record.

**Shared fix direction.**
- One `GraphiteTestSupport` target holds every fake, once (`CC-ARCH-09`).
- Each protocol with more than one conformer gets a parameterised contract suite that production, fake and in-memory conformers all run.
- The Swift–JavaScript boundary gets one JSON fixture of request → expected-answer cases, run by a Swift test against `CommunityPluginVaultBridge` and by a Node test against the test host (`LSP-PLUGIN-01`).
- Test-only entry points are deleted, and tests drive the production path through an injected port (`AudioRecorder` for `LSP-LECTURE-03`).

### 2.6 Identity and equality do not mean "the same thing"

**What it is.** An `Identifiable.id`, a fold key or a recognition test is derived from display text, rewritten text or a position that shifts on unrelated edits. Or `==` ignores an input that changes behaviour.

**Where it occurs (7 findings, 5 areas).**
- VAULT: `LSP-VAULT-04` (`Bookmark.id` includes a group's title).
- CANVAS: `LSP-CANVAS-03` (a duplicate `id` gets the element index).
- LECTURE: `LSP-LECTURE-04` (a bookmark is recognised by its label prefix).
- READING: `LSP-READING-02` (callout key from the displayed title), `LSP-READING-05` (`NoteThemeStyle ==` ignores the fallback accent), `LSP-READING-06` (block ids from a per-build counter; build equality from a hash).
- SHELL: `LSP-SHELL-04` (four `==` that ignore closures on purpose).

**Evidence.**
- *Bookmark.* `id` joins type, `ctime`, then path, query, url or title ([Bookmarks.swift:85-87](../../../Sources/GraphiteCore/Bookmarks.swift#L85-L87)). Renaming a group therefore changes its identity.
- *Canvas card.* A repeated card `id` becomes `id + "\u{1}" + elementIndex` ([CanvasFile.swift:203](../../../Sources/GraphiteCore/CanvasFile.swift#L203), [CanvasFile.swift:278-281](../../../Sources/GraphiteCore/CanvasFile.swift#L278-L281)).
- *PDF bookmark.* `isBookmark` requires `label.hasPrefix("Page ")` ([PDFSession.swift:166-171](../../../Sources/GraphiteUI/PDFSession.swift#L166-L171)).
- *Theme style.* `NoteThemeStyle ==` compares `tokens.fingerprint` only ([NoteThemeStyle.swift:107](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L107)).
- *Palette actions.* `TemplatePickerAction ==` and `DocumentRenameAction ==` return `true` ([QuickPalette.swift:419](../../../Sources/GraphiteUI/QuickPalette.swift#L419), [QuickPalette.swift:434](../../../Sources/GraphiteUI/QuickPalette.swift#L434)). Their invariant is documented on the type ([QuickPalette.swift:415-416](../../../Sources/GraphiteUI/QuickPalette.swift#L415-L416)).

**Cost.**
- 1 defect: BUG-READING-02 (a callout expanded in reading view reads as collapsed in Live Preview and Read Aloud).
- "Remove" can act on the wrong bookmark (`LSP-VAULT-04`). A selection can move to another card after an edit (`LSP-CANVAS-03`). An author's "Page 5" outline entry is removable as a user bookmark (`LSP-LECTURE-04`).
- Every block after an insertion gets a new identity, so SwiftUI rebuilds every row (`LSP-READING-06`).

**Shared fix direction.**
- Identity comes from structured, stable content: the written source line, the stored `id` plus occurrence count, the object, or a session UUID assigned at load.
- Equality compares every stored input that changes behaviour.
- A deliberate partial `==` keeps its documented invariant and a pinning test, as the four in SHELL do (`LSP-SHELL-04`, kept for large-vault performance).

## 3. Largest offenders

Ranked by defects traced, then by the number of substitutes that disagree.

| # | Type, function or rule | Numbers | Defects | Findings |
| ---: | --- | --- | --- | --- |
| 1 | Markdown line rules (`MarkdownEditing`, `MarkdownStyleScanner`, `NotePreviewDocument`, `TextColorMarkup`, `MarkdownCodeRanges`, `NoteBlocks`, `CodeLineScanner`, `LinkCompletion`) | Fence rule 7 implementations, list marker 7, ATX heading 5 (+ swift-markdown), display math 5, thematic break 5, indentation columns 5, code span 4. 1 parity test. | BUG-MDCORE-02, -03, -04 | `LSP-MDCORE-01` |
| 2 | `NativeMarkdownEditor` Mac `Coordinator` against iPad `Coordinator` | 6 session duties unserved on the Mac (12 serving lines, all in the iPad block); 1 initializer parameter accepted and dropped; different undo fallback, suspend and scroll restore | BUG-EDITOR-01, -02, -03, -04 | `LSP-EDITOR-01`, `-02`, `-03`, `-06` |
| 3 | Link resolution | 7 entry-point implementations in 4 modules plus the runtime JavaScript (section 7); the in-memory Bases provider alone differs from the index on 4 rules | BUG-ARCH-05 (= BUG-READING-03) | `LSP-ARCH-02`, `LSP-READING-03`, `LSP-VAULT-03`, `LSP-BASES-01` |
| 4 | `ReadAloudSpeaking` and its 2 adapters | 16 requirements, 10 defaulted; 7 contract points differ; 6 private test fakes; 0 contract suites | BUG-VOICE-04, -05, -08 | `LSP-VOICE-01`, `-02`, `-04` |
| 5 | Read Aloud "stop" | 4 functions named `stop` with 4 scopes; the player's 2 Stop buttons call different ones | BUG-VOICE-01, -02 | `LSP-VOICE-03` |
| 6 | `test-vault-host.js` against `CommunityPluginVaultBridge` and `CommunityPluginHost` | 7 bridge behaviours differ, plus editor-change refusal and the `vault.changes` payload; 84 Node tests run against it | BUG-PLUGIN-03, BUG-RUNTIME-01 (hidden) | `LSP-PLUGIN-01`, `LSP-RUNTIME-01`, `LSP-RUNTIME-02` |
| 7 | Reading-view fold keys (`MarkdownPreview` heading and `CalloutView` keys) | Heading key formula written 3 times (1 Core, 2 reading view); callout key from the prepared title; 0 tests pin reading-view keys | BUG-READING-01, -02 | `LSP-READING-01`, `LSP-READING-02` |
| 8 | Media classification (`DocumentKind`, `MediaFileKind`, `RecordingRecoveryFolder.mediaExtensions`) | 3 lists; 6 against 11 audio/video extensions; 5 extensions classified differently | BUG-ARCH-01 | `LSP-ARCH-01` |
| 9 | `BaseInMemoryRecordProvider` against `BaseIndexRecordProvider` | 4 rule differences; 21 Core test call sites against 5 index-provider sites; 3 initializers default `provider` to `nil`; failures travel in a side channel | — (tests pass on rules production does not run) | `LSP-BASES-01`, `LSP-BASES-02` |
| 10 | Mac `GraphitePDFView` | 15 inputs, 10 ignored, 5 marked "accepted so both platforms share one call" | — (markup and Copy Link to Page silently absent on the Mac) | `LSP-LECTURE-02` |

The next two in the ranking, each with one defect:

- `fileCount(named:excluding:)`: 1 of 2 name counts uses ASCII-only folding (BUG-VAULT-01, `LSP-VAULT-01`).
- Mac `CanvasBoardHost`: 3 of 7 gestures (BUG-CANVAS-03, `LSP-CANVAS-02`).

## 4. What to keep for this principle

The cleanup must imitate these designs. Each one already meets the substitution contract, and an area document recorded it in its "What to keep" section.

| Design | Evidence | Why it meets LSP | Recorded in |
| --- | --- | --- | --- |
| Narrow ports with a real substitution: `MarkdownStyledTextView` (5 members, both text views) and `RetainableMarkdownEditor` (3 members, both coordinators plus a test fake) | [MarkdownEditorStyling.swift:12-22](../../../Sources/GraphiteUI/MarkdownEditorStyling.swift#L12-L22), [MarkdownEditorRetention.swift:10-18](../../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L10-L18), [MarkdownEditorRetentionTests.swift:8](../../../Tests/GraphiteUITests/MarkdownEditorRetentionTests.swift#L8) | Exactly the protocol use `RULES.md` allows. The shared styling engine works on either platform's view. The port is right; only the Mac's suspend behaviour behind it differs (`LSP-EDITOR-02`). | EDITOR §6 |
| Synthetic camera through the production writer | `SyntheticCaptureSource` ([VideoRecordingTestSupport.swift:15](../../../Tests/GraphiteAppleTests/VideoRecordingTestSupport.swift#L15)); seam in [VideoCapture.swift:81-102](../../../Sources/GraphiteApple/VideoCapture.swift#L81-L102) | The fake replaces only the hardware. Writer, parts and published MP4 are production code, exercised by 21 tests. The template for every other fake. | LECTURE §6 row 23 |
| Hand-written mirror pinned by a parity test | `NoteFolding.isListItem` against `MarkdownEditing.listLine` over 34 lines ([NoteFoldingTests.swift:75-81](../../../Tests/GraphiteCoreTests/NoteFoldingTests.swift#L75-L81)); region moving checked against finding again ([NoteFoldingTests.swift:83-112](../../../Tests/GraphiteCoreTests/NoteFoldingTests.swift#L83-L112)) | A fast duplicate coexists with one owner because a test proves they agree. The model for every performance mirror under rule LSP 1. | MDCORE §6 rows 7–8 |
| Tokenizer that reproduces SQLite's `unicode61` | [SearchQuery.swift:393-553](../../../Sources/GraphiteCore/SearchQuery.swift#L393-L553); `CoreSearchQueryUnicode61AgreementTests` | The Swift matcher substitutes for FTS5 conditions only because an agreement test pins them equal. | VAULT §6 row 15 |
| Supersets marked as such | `SearchSQLCompiler` conditions are supersets unless marked exact ([VaultSearch.swift:279-333](../../../Sources/GraphiteIndex/VaultSearch.swift#L279-L333)); Bases prefilter as a superset ([BaseRecordPrefilter.swift:38-40](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L38-L40)) | Each approximation states its direction, so `NOT` and `or` never produce a false negative. | VAULT §6 row 16, BASES §6 |
| Edits as splices with exact inverse patches; a patch for another version is refused | [CanvasFileEditing.swift:56-70](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L56-L70); [CanvasEditingTests.swift:271-275](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L271-L275) | Undo substitutes the old bytes exactly, and a mismatched input yields `nil`, never a misapplied edit. | CANVAS §6 |
| `HistoryCanvasView` subclasses honour the base; `PencilDrawingChange` refuses foreign drawings | [PencilDrawingChange.swift:29-125](../../../Sources/GraphiteApple/PencilDrawingChange.swift#L29-L125) | Every canvas is a valid `HistoryCanvasView` (INK verdict). A history step from another document is refused, not applied. | INK §6 |
| Typed failure answers at the plugin bridge | Requests decoded into private `Decodable` structs; every failure returned as `{failure: {kind, message}}` ([CommunityPluginVaultBridge.swift:32-42](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L32-L42)); `runtime.receive` never throws (RUNTIME §6 row 16) | A malformed message is `invalidData`, never a crash or a default, so callers can rely on one failure contract. | PLUGIN §6 row 1, RUNTIME §6 row 16 |
| Stand-ins that fail visibly | Unsupported APIs throw a named error, reported once per plugin and feature; desktop modules fail when used, naming the member (RUNTIME §6 rows 8–9) | No fake success: a substitute that cannot do the work says so. The opposite of `LSP-RUNTIME-06`. | RUNTIME §6 |
| ES5 class shim keeps `instanceof` exact | `callableClass` gives the callable the class's own prototype ([community-plugin-runtime-plugins.js:47-60](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L47-L60)) | A plugin subclass built for ES5 is substitutable for Obsidian's ES2015 class, literally. | RUNTIME §6 row 10 |
| Value equality that is reflexive and consistent with hashing | `BaseValue` equality with NaN and an exhaustive switch ([BaseValue.swift:341-398](../../../Sources/GraphiteCore/BaseValue.swift#L341-L398)); PDF stroke fingerprint whose `hash` uses a subset of the `==` fields ([PDFPencilInk.swift:19-76](../../../Sources/GraphiteApple/PDFPencilInk.swift#L19-L76)) | `Hashable` laws hold, so sets and dictionaries behave. | BASES §6, LECTURE §6 row 8 |
| Identity by object, not index | PDF pages in selection, rows and drags ([PDFPagesSidebar.swift:205-231](../../../Sources/GraphiteUI/PDFPagesSidebar.swift#L205-L231)) | Inserting or moving pages never moves a selection onto another page. The fix shape for `LSP-CANVAS-03` and `LSP-READING-06`. | LECTURE §6 row 29 |
| Platform-neutral model, platform builders | Context menu model rendered by UIKit and AppKit builders, tested on the Mac ([EditorContextMenu.swift:35-59](../../../Sources/GraphiteUI/EditorContextMenu.swift#L35-L59)) | One list of items for both platforms, so the variants cannot drift. The shape pattern 2.2 must adopt. | EDITOR §6 |
| Unreadable data kept and reported, not emptied | `VaultLibrary` keeps unreadable entries and an unreadable whole list ([VaultLibrary.swift:67-109](../../../Sources/GraphiteUI/VaultLibrary.swift#L67-L109)); unreadable plugin folders listed with their reason ([CommunityPluginInventory.swift:134-146](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L134-L146)); a failed Base lookup surfaced before publishing ([BaseDocumentModel.swift:212-215](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L212-L215)) | "Could not read" stays distinct from "nothing there". The model for pattern 2.3. | SHELL §6, ARCH §6, PLUGIN §6 row 12, BASES §6 |
| Deliberate partial equality, documented and measured | `FileTreeRows ==` and `VaultEntryRow ==` with redraw tests ([VaultSidebar.swift:572-645](../../../Sources/GraphiteUI/VaultSidebar.swift#L572-L645), [UiRedrawAvoidanceTests.swift](../../../Tests/GraphiteUITests/UiRedrawAvoidanceTests.swift)) | Allowed under rule LSP 3 because the invariant is stated and pinned. Keeps a 25,000-file tree responsive. | SHELL §6 |

## 5. Index of findings

All 58 `LSP` findings, generated from [findings-index.md](../findings-index.md), ordered by severity, then area.

| ID | Area | Severity | Title |
| --- | --- | --- | --- |
| [LSP-ARCH-01](../cross-cutting/architecture.md#lsp-arch-01-two-media-vocabularies-disagree-about-which-files-are-audio-and-video) | ARCH | High | Two media vocabularies disagree about which files are audio and video |
| [LSP-BASES-01](../areas/bases.md#lsp-bases-01-the-in-memory-and-index-providers-disagree-on-four-rules-and-core-tests-pin-the-one-production-never-uses) | BASES | High | The in-memory and index providers disagree on four rules, and Core tests pin the one production never uses |
| [LSP-EDITOR-01](../areas/editor.md#lsp-editor-01-the-mac-editor-does-not-serve-six-session-duties-the-ipad-editor-serves) | EDITOR | High | The Mac editor does not serve six session duties the iPad editor serves |
| [LSP-MDCORE-01](../areas/mdcore.md#lsp-mdcore-01-the-same-markdown-line-gets-different-answers-from-parallel-implementations-of-one-rule) | MDCORE | High | The same Markdown line gets different answers from parallel implementations of one rule |
| [LSP-PLUGIN-01](../areas/plugin.md#lsp-plugin-01-the-node-tests-vault-host-differs-from-the-swift-bridge-in-seven-behaviours-one-of-which-hides-a-bug) | PLUGIN | High | The Node tests' vault host differs from the Swift bridge in seven behaviours, one of which hides a bug |
| [LSP-READING-01](../areas/reading.md#lsp-reading-01-reading-view-computes-heading-fold-keys-from-rewritten-text-notefolding-from-the-source-line) | READING | High | Reading view computes heading fold keys from rewritten text; `NoteFolding` from the source line |
| [LSP-VAULT-01](../areas/vault.md#lsp-vault-01-two-implementations-of-how-many-files-share-this-name-disagree-on-non-ascii-capitals) | VAULT | High | Two implementations of "how many files share this name" disagree on non-ASCII capitals |
| [LSP-VOICE-01](../areas/voice.md#lsp-voice-01-the-system-voice-and-neural-adapters-honour-different-contracts-for-the-same-readaloudspeaking-calls) | VOICE | High | The system-voice and neural adapters honour different contracts for the same `ReadAloudSpeaking` calls |
| [LSP-ARCH-02](../cross-cutting/architecture.md#lsp-arch-02-link-resolution-has-four-implementations-with-different-rules) | ARCH | Medium | Link resolution has four implementations with different rules |
| [LSP-ARCH-03](../cross-cutting/architecture.md#lsp-arch-03-the-only-named-fake-has-safer-failure-semantics-than-production) | ARCH | Medium | The only named fake has safer failure semantics than production |
| [LSP-BASES-02](../areas/bases.md#lsp-bases-02-a-failed-index-lookup-is-returned-as-missing-and-the-failure-travels-in-a-side-channel) | BASES | Medium | A failed index lookup is returned as "missing", and the failure travels in a side channel |
| [LSP-BASES-03](../areas/bases.md#lsp-bases-03-the-editors-setters-do-not-round-trip-keys-the-reader-accepts-under-other-names) | BASES | Medium | The editor's setters do not round-trip keys the reader accepts under other names |
| [LSP-CANVAS-01](../areas/canvas.md#lsp-canvas-01-an-unreadable-canvas-reports-zero-links-instead-of-a-failure) | CANVAS | Medium | An unreadable canvas reports zero links instead of a failure |
| [LSP-CANVAS-02](../areas/canvas.md#lsp-canvas-02-the-mac-and-uikit-variants-of-canvasboardhost-offer-different-behaviour-under-one-name) | CANVAS | Medium | The Mac and UIKit variants of `CanvasBoardHost` offer different behaviour under one name |
| [LSP-EDITOR-02](../areas/editor.md#lsp-editor-02-suspending-and-dismantling-differ-between-the-two-editors) | EDITOR | Medium | Suspending and dismantling differ between the two editors |
| [LSP-EDITOR-03](../areas/editor.md#lsp-editor-03-graphites-own-edits-follow-different-undo-rules-per-platform) | EDITOR | Medium | Graphite's own edits follow different undo rules per platform |
| [LSP-EDITOR-04](../areas/editor.md#lsp-editor-04-a-styler-mode-that-production-never-uses-is-pinned-by-a-test-that-describes-the-mac-wrongly) | EDITOR | Medium | A styler mode that production never uses is pinned by a test that describes the Mac wrongly |
| [LSP-INK-01](../areas/ink.md#lsp-ink-01-the-three-drawing-format-readers-disagree-on-what-a-damaged-file-is) | INK | Medium | The three drawing-format readers disagree on what a damaged file is |
| [LSP-INK-03](../areas/ink.md#lsp-ink-03-hold-to-shape-and-the-lift-recognize-the-same-stroke-through-two-different-inputs) | INK | Medium | Hold-to-shape and the lift recognize the same stroke through two different inputs |
| [LSP-LECTURE-01](../areas/lecture.md#lsp-lecture-01-two-digital-signature-detectors-apply-different-rules-production-uses-the-one-the-documents-do-not-name) | LECTURE | Medium | Two digital-signature detectors apply different rules; production uses the one the documents do not name |
| [LSP-LECTURE-02](../areas/lecture.md#lsp-lecture-02-the-mac-graphitepdfview-accepts-15-inputs-and-ignores-10-of-them) | LECTURE | Medium | The Mac `GraphitePDFView` accepts 15 inputs and ignores 10 of them |
| [LSP-LECTURE-03](../areas/lecture.md#lsp-lecture-03-tests-drive-recordingcontroller-through-adoptrecording-which-sets-states-production-never-reaches-that-way) | LECTURE | Medium | Tests drive `RecordingController` through `adoptRecording`, which sets states production never reaches that way |
| [LSP-LECTURE-04](../areas/lecture.md#lsp-lecture-04-a-bookmarks-identity-is-read-back-from-its-display-label) | LECTURE | Medium | A bookmark's identity is read back from its display label |
| [LSP-LECTURE-05](../areas/lecture.md#lsp-lecture-05-failed-folder-reads-in-recording-recovery-are-returned-as-empty-results) | LECTURE | Medium | Failed folder reads in recording recovery are returned as empty results |
| [LSP-PLUGIN-02](../areas/plugin.md#lsp-plugin-02-seven-reads-turn-a-failure-into-an-empty-result) | PLUGIN | Medium | Seven reads turn a failure into an empty result |
| [LSP-PLUGIN-03](../areas/plugin.md#lsp-plugin-03-send-hides-the-runtimes-failure-kinds-and-treats-a-non-object-answer-as-success) | PLUGIN | Medium | `send` hides the runtime's failure kinds and treats a non-object answer as success |
| [LSP-READING-02](../areas/reading.md#lsp-reading-02-calloutview-keys-its-expansion-by-the-displayed-title-in-reading-view-and-by-the-written-title-elsewhere) | READING | Medium | `CalloutView` keys its expansion by the displayed title in reading view and by the written title elsewhere |
| [LSP-READING-03](../areas/reading.md#lsp-reading-03-two-link-resolvers-with-different-answers) | READING | Medium | Two link resolvers with different answers |
| [LSP-READING-04](../areas/reading.md#lsp-reading-04-wikilink-display-text-is-computed-by-two-rules) | READING | Medium | Wikilink display text is computed by two rules |
| [LSP-RUNTIME-01](../areas/runtime.md#lsp-runtime-01-the-node-test-host-accepts-editor-changes-that-production-refuses) | RUNTIME | Medium | The Node test host accepts editor changes that production refuses |
| [LSP-RUNTIME-02](../areas/runtime.md#lsp-runtime-02-tests-pin-a-vaultchanges-shape-that-production-never-sends) | RUNTIME | Medium | Tests pin a `vault.changes` shape that production never sends |
| [LSP-SHELL-01](../areas/shell.md#lsp-shell-01-two-implementations-of-read-this-note-aloud-disagree-about-folded-text) | SHELL | Medium | Two implementations of "read this note aloud" disagree about folded text |
| [LSP-SHELL-02](../areas/shell.md#lsp-shell-02-failed-reads-are-shown-as-empty-results) | SHELL | Medium | Failed reads are shown as empty results |
| [LSP-VAULT-02](../areas/vault.md#lsp-vault-02-the-conflict-version-test-store-succeeds-where-production-fails) | VAULT | Medium | The conflict-version test store succeeds where production fails |
| [LSP-VAULT-03](../areas/vault.md#lsp-vault-03-graphlinkresolver-re-implements-resolvedpaths-kept-equal-only-by-a-test) | VAULT | Medium | `GraphLinkResolver` re-implements `resolvedPaths`, kept equal only by a test |
| [LSP-VAULT-04](../areas/vault.md#lsp-vault-04-identity-and-equality-differ-in-four-identifiable-types-one-identity-changes-on-rename) | VAULT | Medium | Identity and equality differ in four identifiable types; one identity changes on rename |
| [LSP-VOICE-02](../areas/voice.md#lsp-voice-02-protocol-default-implementations-silently-drop-request-fields-and-the-test-fakes-run-through-them) | VOICE | Medium | Protocol default implementations silently drop request fields, and the test fakes run through them |
| [LSP-VOICE-03](../areas/voice.md#lsp-voice-03-four-functions-named-stop-have-four-scopes-and-the-players-two-stop-buttons-call-different-ones) | VOICE | Medium | Four functions named `stop` have four scopes, and the player's two Stop buttons call different ones |
| [LSP-ARCH-04](../cross-cutting/architecture.md#lsp-arch-04-pdf-sessions-fall-back-to-a-writer-without-the-vaults-presenter) | ARCH | Low | PDF sessions fall back to a writer without the vault's presenter |
| [LSP-CANVAS-03](../areas/canvas.md#lsp-canvas-03-duplicate-id-cards-and-connections-get-identities-that-change-when-earlier-entries-are-removed) | CANVAS | Low | Duplicate-`id` cards and connections get identities that change when earlier entries are removed |
| [LSP-EDITOR-05](../areas/editor.md#lsp-editor-05-one-image-import-rule-has-three-implementations-with-different-results) | EDITOR | Low | One image-import rule has three implementations with different results |
| [LSP-EDITOR-06](../areas/editor.md#lsp-editor-06-the-mac-editor-never-records-that-the-cursor-was-placed) | EDITOR | Low | The Mac editor never records that the cursor was placed |
| [LSP-INK-02](../areas/ink.md#lsp-ink-02-selectedpicturescontent-conforms-to-the-editing-protocol-with-five-no-ops) | INK | Low | `SelectedPicturesContent` conforms to the editing protocol with five no-ops |
| [LSP-INK-04](../areas/ink.md#lsp-ink-04-the-drawing-editors-history-drops-a-refused-step-silently) | INK | Low | The drawing editor's history drops a refused step silently |
| [LSP-MDCORE-02](../areas/mdcore.md#lsp-mdcore-02-private-use-marker-protection-has-two-mechanisms-with-different-results) | MDCORE | Low | Private-use marker protection has two mechanisms with different results |
| [LSP-MDCORE-03](../areas/mdcore.md#lsp-mdcore-03-tests-pin-two-wrappers-production-never-calls) | MDCORE | Low | Tests pin two wrappers production never calls |
| [LSP-PLUGIN-04](../areas/plugin.md#lsp-plugin-04-communitypluginshowncodeblock-serves-blocks-sections-and-views-with-different-contracts) | PLUGIN | Low | `CommunityPluginShownCodeBlock` serves blocks, sections and views with different contracts |
| [LSP-READING-05](../areas/reading.md#lsp-reading-05-notethemestyle-equality-ignores-one-of-its-inputs) | READING | Low | `NoteThemeStyle` equality ignores one of its inputs |
| [LSP-READING-06](../areas/reading.md#lsp-reading-06-block-identity-is-positional-and-build-equality-is-a-hash) | READING | Low | Block identity is positional, and build equality is a hash |
| [LSP-RUNTIME-03](../areas/runtime.md#lsp-runtime-03-vaultconfig-and-vaultgetconfig-answer-differently-for-the-same-keys) | RUNTIME | Low | `Vault.config` and `Vault.getConfig` answer differently for the same keys |
| [LSP-RUNTIME-04](../areas/runtime.md#lsp-runtime-04-two-functions-decide-a-leafs-placement-and-disagree-for-split-leaves) | RUNTIME | Low | Two functions decide a leaf's placement and disagree for split leaves |
| [LSP-RUNTIME-05](../areas/runtime.md#lsp-runtime-05-objectvalueentries-is-an-object-or-an-array-of-pairs-depending-on-who-built-it) | RUNTIME | Low | `ObjectValue.entries` is an object or an array of pairs depending on who built it |
| [LSP-RUNTIME-06](../areas/runtime.md#lsp-runtime-06-stand-ins-that-report-success-for-work-they-did-not-do) | RUNTIME | Low | Stand-ins that report success for work they did not do |
| [LSP-SHELL-03](../areas/shell.md#lsp-shell-03-platform-variants-of-one-function-behave-differently) | SHELL | Low | Platform variants of one function behave differently |
| [LSP-SHELL-04](../areas/shell.md#lsp-shell-04-equality-that-ignores-content-is-used-deliberately-in-four-types) | SHELL | Low | Equality that ignores content is used deliberately in four types |
| [LSP-VOICE-04](../areas/voice.md#lsp-voice-04-the-sessions-voice-without-word-timing-memory-keys-on-the-apple-voice-even-when-a-neural-voice-speaks) | VOICE | Low | The session's "voice without word timing" memory keys on the Apple voice even when a neural voice speaks |
| [LSP-VOICE-05](../areas/voice.md#lsp-voice-05-two-word-at-a-playback-time-implementations-disagree-on-silence) | VOICE | Low | Two "word at a playback time" implementations disagree on silence |
| [LSP-VOICE-06](../areas/voice.md#lsp-voice-06-on-the-mac-the-recognized-word-highlight-colour-does-not-follow-appearance-changes) | VOICE | Low | On the Mac the recognized-word highlight colour does not follow appearance changes |

## 6. Rules for new code

Each rule is checkable in review or by a script. "Check" is the review step. "Answers" lists the findings that demand the rule.

**LSP 1. One owner per rule; a performance mirror needs a parity test.** A question about the same input (is this line a fence, which file does this link name, is this extension audio, what key does this heading get) must be answered by exactly one function, and every other site must call it. A hand-written fast copy is allowed only when a corpus test asserts that it agrees with the owner on every case.
- Check: grep the question's keywords (`isFence`, fence-marker prefix tests, `lowercased()` on names, extension string lists) for a second definition; a second definition without a test that names both is rejected.
- Answers: `LSP-MDCORE-01`, `LSP-MDCORE-02`, `LSP-ARCH-01`, `LSP-ARCH-02`, `LSP-READING-01`, `LSP-READING-03`, `LSP-READING-04`, `LSP-VAULT-01`, `LSP-VAULT-03`, `LSP-EDITOR-05`, `LSP-LECTURE-01`, `LSP-VOICE-05`, `LSP-SHELL-01`, `LSP-RUNTIME-03`, `LSP-RUNTIME-04`, `LSP-INK-03`.

**LSP 2. One name, one platform contract.** A type that has a UIKit body and an AppKit body under one name must serve the same inputs, gestures and duties on both, and must not declare an input one body ignores. A body that cannot serve an input must be a different, clearly named type, or the input must be an optional sub-value that exists only where it is served.
- Check: for each `#if canImport(UIKit)` / `#else` pair, every stored property and initializer parameter is read in both branches (grep the property name inside each branch); the pair has one shared contract test run on both platforms.
- Answers: `LSP-EDITOR-01`, `LSP-EDITOR-02`, `LSP-EDITOR-03`, `LSP-EDITOR-06`, `LSP-LECTURE-02`, `LSP-CANVAS-02`, `LSP-SHELL-03`, `LSP-VOICE-06`.

**LSP 3. Equality compares every behavioural input; a deliberate partial `==` states its invariant and is pinned.** A type's `==` and `hash(into:)` must cover every stored input that changes what it renders or does. A partial `==` (closures ignored, fingerprint only) is allowed only when its doc comment states the invariant and a redraw or equality test pins it.
- Check: compare the stored properties with the fields named in `==`; any property missing from `==` needs a doc comment on the `==` and a test that names the type.
- Answers: `LSP-READING-05`, `LSP-READING-06`, `LSP-SHELL-04`, `LSP-VAULT-04`.

**LSP 4. Identity comes from stable structured content, never from display text or position.** An `Identifiable.id`, a fold key, a persisted key and a recognition test must derive from the source line, a stored identifier plus occurrence count, an object identity or a session UUID. They must not derive from a label the user can rename or translate, a rewritten display string or an element index.
- Check: grep `var id` and `Key` builders for `title`, `label`, `text`, `.count`, `index`, `hasPrefix` inputs; each hit needs a recorded reason.
- Answers: `LSP-VAULT-04`, `LSP-CANVAS-03`, `LSP-LECTURE-04`, `LSP-READING-01`, `LSP-READING-02`, `LSP-READING-06`.

**LSP 5. A failure is never an empty result.** A read that can fail must throw a typed error (with a distinct `notFound` where absence is legitimate) or return a result enum with an `unreadable` case. It must not return `[]`, `[:]`, `nil` or a default for an error, and it must not record the error in a side channel.
- Check: grep `try?`, `?? []`, `?? [:]`, `?? nil` in production reads; each hit shows either a same-line comment saying why it is harmless or a typed failure. Protocol requirements that can fail are marked `throws`.
- Answers: `LSP-SHELL-02`, `LSP-CANVAS-01`, `LSP-LECTURE-05`, `LSP-PLUGIN-02`, `LSP-PLUGIN-03`, `LSP-BASES-02`, `LSP-INK-01`.

**LSP 6. A success answer is computed from what happened.** A method that reports success, a count or a stand-in answer must derive it from the returned outcomes of the work (items saved, file actually moved), not from the number of attempts, from "a file exists at the destination" or from a constant.
- Check: every `return true`, `savedCount`, `count` and `{ ok: true }` has the outcome value it summarises in scope; a stand-in that cannot do the work throws or reports "unsupported" by name.
- Answers: `LSP-RUNTIME-06`, `LSP-PLUGIN-03`, `LSP-PLUGIN-01`.

**LSP 7. A protocol states its contract, and its conformers meet all of it.** Each protocol with more than one conformer must document ranges, events, failures and which request fields it must honour, and every conformer must honour them. A capability an adapter lacks is a value it reports (`supportedSpeedRange`, word timing per request), never a silent default or a clamped value.
- Check: the protocol's doc comment lists each requirement's preconditions and failure answers; diff two conformers' bodies for the same requirement and justify each difference in the comment.
- Answers: `LSP-VOICE-01`, `LSP-VOICE-04`, `LSP-BASES-01`, `LSP-INK-04`, `LSP-PLUGIN-04`, `LSP-RUNTIME-05`.

**LSP 8. No forwarding defaults and no no-op conformances.** A protocol extension must not provide a default for a requirement that forwards to another with fewer fields, and a conformer must not implement a mutating requirement as an empty body. A conformer that would stub a requirement means the protocol is too wide and must be split.
- Check: grep `extension .*Protocol` for `func` bodies that call a sibling requirement with literals; grep conformers for empty `{ }` bodies and `.infinite` placeholders. Neither is accepted.
- Answers: `LSP-VOICE-02`, `LSP-INK-02`, `LSP-EDITOR-01`.

**LSP 9. No default argument swaps in a different implementation.** An optional dependency (`provider: X? = nil`, `?? AtomicFileWriter()`) must not fall back to a weaker implementation with different rules. A missing dependency is a compile error or an explicit parameter; the production composition root supplies the real one.
- Check: grep `= nil` on protocol-typed initializer parameters and `?? \w+\(\)` on dependencies in Sources; each hit is removed or justified.
- Answers: `LSP-BASES-01`, `LSP-ARCH-04`.

**LSP 10. Every interface with more than one implementation has one parameterised contract suite.** The production conformer, each fake and each in-memory implementation must run the same test suite, named `<Protocol>ContractTests`. A new conformer is added to the suite in the same change.
- Check: for every protocol with two or more conformers (grep `: ProtocolName`), a test file `ProtocolNameContractTests` exists and lists every conformer.
- Answers: `LSP-BASES-01`, `LSP-VAULT-02`, `LSP-VAULT-03`, `LSP-ARCH-03`, `LSP-VOICE-01`, `LSP-EDITOR-01`, `LSP-EDITOR-03`, `LSP-INK-01`, `LSP-LECTURE-01`.

**LSP 11. A fake replaces only the hardware or the platform, and keeps production semantics.** A test double must fail where production fails, refuse what production refuses and live once in a test-support target. It must never make an operation look safer or simpler than production.
- Check: a fake's methods contain no `try?`, no default success and no state that production cannot reach; fakes are declared only under the test-support target (grep `final class .*Fake|Test.*Store` outside it).
- Answers: `LSP-VAULT-02`, `LSP-ARCH-03`, `LSP-VOICE-02`, `LSP-BASES-01`, `LSP-LECTURE-03`.

**LSP 12. A cross-language test host runs the production fixture.** A JavaScript or other host standing in for a Swift bridge must run one shared JSON fixture of request, expected-answer and expected-failure cases that a Swift test also runs against the production bridge. Behaviour that production does not have must not be added to the host, and behaviour production has must not be left out.
- Check: the fixture file exists, is referenced by one Swift test and one Node test, and every bridge operation appears in it at least once.
- Answers: `LSP-PLUGIN-01`, `LSP-RUNTIME-01`, `LSP-RUNTIME-02`, `LSP-ARCH-02`.

**LSP 13. No test-only mode, entry point or state.** A production type must not carry a property, a branch or a method that only a test sets or calls. Tests reach states through the production path with an injected port, and a test that pins a function production never calls moves to the function production calls.
- Check: for each new `var`/`func` in Sources, grep its writers and callers; a member whose only writer or caller is under `Tests/` is rejected.
- Answers: `LSP-EDITOR-04`, `LSP-LECTURE-03`, `LSP-MDCORE-03`, `LSP-LECTURE-01`, `LSP-VOICE-05`.

**LSP 14. A vocabulary is read and written through one registry.** A key, alias or option name that a reader accepts under several spellings must come from one typed registry (canonical key plus read aliases) used by the reader and the editor, and a setter must write the canonical key and remove every alias. Reader and writer must round-trip: parse, set, parse yields the set value.
- Check: grep string literals of keys in the reader and the editor; each literal appears once in the registry file. A round-trip test exists for each registered key.
- Answers: `LSP-BASES-03`, `LSP-ARCH-01`, `LSP-RUNTIME-05`.

**LSP 15. A function name states its scope; one scope is one function.** Functions that stop, cancel, clear or reset must take or carry a scope enum, or have a name that states it. Two functions with the same verb in one feature must differ by scope in the signature, and every control for one user action must call the same function.
- Check: grep `func stop`, `func cancel`, `func reset` per feature; more than one hit without a scope parameter is rejected.
- Answers: `LSP-VOICE-03`, `LSP-VOICE-04`.

**LSP 16. Recognise one thing once, from one input.** When two inputs can trigger the same recognition (preview and commit, hold and lift), the result is computed once, in one coordinate space, and the commit uses the previewed result. Tests must feed the two paths different inputs, including zoom other than 1.
- Check: grep the recogniser's call sites; one call site per recognised object, and a test with a non-identity transform.
- Answers: `LSP-INK-03`, `LSP-INK-04`, `LSP-READING-01`.

**LSP 17. Refusals are reported and every owner of a step honours the same refusal.** When an undo, history or patch step is refused, the owner must report it and keep the history consistent. Two owners of one change type must use one helper with one refusal behaviour.
- Check: every `guard ... else { return }` in a history application path calls a reporting function; two call sites of `reverting(`/`reapplying(` share a helper.
- Answers: `LSP-INK-04`, `LSP-EDITOR-03`.

## 7. Corrections

Disagreements between area documents, settled from the snapshot.

| # | Disagreement | Decision |
| ---: | --- | --- |
| 1 | The BASES verdict says "about 22 Core test call sites" run the in-memory provider. `LSP-BASES-01` says 21. | 21 is right. Grep of `BaseEvaluator(formulas` and `BaseQueryEngine(` over `Tests/GraphiteCoreTests` finds 22 call sites, and exactly 1 passes `provider:` ([CoreAreaHandoffTests.swift:265](../../../Tests/GraphiteCoreTests/CoreAreaHandoffTests.swift#L265)). 21 run the in-memory provider. Sections 1 and 3 use 21. |
| 2 | The SHELL verdict says failed reads show as empty lists "in 4 places". `LSP-SHELL-02` counts 5 sites. | 5 sites in 3 files is right: 3 in [FileRecoverySheet.swift](../../../Sources/GraphiteUI/FileRecoverySheet.swift) (lines 60, 101, 145), the quick switcher and `resolveLink`. The verdict undercounts by merging two sites. Section 1 uses 5. |
| 3 | `LSP-ARCH-02` says link resolution has 4 implementations. Section 2.1 and section 3 say 7 entry points. | Both are right and count different things. ARCH-02 counts 4 rule sets with different answers: the workspace resolver, the reading-view resolver, the graph's in-memory resolver and the plugin runtime's JavaScript resolver. The 7 entry points add the SQL `resolvedPaths` (`LSP-VAULT-03`) and the two Bases providers, the in-memory one and the index one (`LSP-BASES-01`). Rule LSP 1 applies to all 7. |
| 4 | `LSP-EDITOR-04` says "5 branches" and lists 6 line numbers (508, 551, 562, 568, 907, 933). | 6 is right. Grep `drawsConcealedReplacements` in [MarkdownTextStyler.swift](../../../Sources/GraphiteUI/MarkdownTextStyler.swift) returns the declaration (line 198) and six guarding reads at those six lines. Section 2.5 uses 6. |
