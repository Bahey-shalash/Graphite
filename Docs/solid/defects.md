# Defects

Snapshot: b13dec3 (main, 2026-10-18).

Every `BUG-*` the thirteen area auditors reported (73), checked by a second, independent reader who did not write the report and traced each trigger from caller to outcome in the frozen snapshot. The verifiers found 4 more (`BUG-<AREA>-V<NN>`), and the lead found 1 while re-checking (`BUG-VOICE-L01`). Two reports describe the same defect as another and are kept as aliases, which leaves **76 distinct defects**.

**Verdict:** Confirmed (trigger traced to the wrong outcome) · Latent (code wrong, no current caller reaches it) · Plausible (depends on runtime behaviour that reading cannot settle; the entry says what would) · Refuted (the outcome does not happen).  
**Severity, by reach in the shipped product:** Critical (data loss, wrong destructive action, security or privacy, in normal use) · High (wrong visible behaviour, hard to recover) · Medium (recoverable, or serious only on a fallback path) · Low (cosmetic, rare, latent, debug or test only).

## Summary

| Severity | Confirmed | Latent | Plausible | Refuted | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Critical | 0 | 0 | 0 | 0 | 0 |
| High | 5 | 0 | 0 | 0 | 5 |
| Medium | 33 | 0 | 2 | 0 | 35 |
| Low | 32 | 0 | 3 | 1 | 36 |
| **Total** | 70 | 0 | 5 | 1 | **76** |

By area: SHELL 6, EDITOR 4, READING 5, MDCORE 6, VAULT 3, BASES 5, CANVAS 6, INK 4, LECTURE 4, VOICE 12, PLUGIN 6, RUNTIME 8, ARCH 7.

## Fix before the cleanup starts

These reach users today: every High, and every Confirmed Medium. Phase 0 of the [migration plan](rewrite-foundations.md) fixes each with a regression test before any structural change, so the characterization tests pin correct behaviour. Lows and Plausibles go to the backlog in the order of the table above.

| ID | Severity | Verdict | Defect | Reach |
| --- | --- | --- | --- | --- |
| [BUG-SHELL-03](#bug-shell-03-quitting-on-the-mac-discards-unsaved-edits-of-a-note-that-cannot-be-saved-without-asking) | High | Confirmed | Quitting on the Mac discards unsaved edits of a note that cannot be saved, without asking | Mac only |
| [BUG-MDCORE-01](#bug-mdcore-01-reading-view-parses-a-deeply-nested-markdown-run-without-the-nesting-guard-while-a-post-processing-plugin-is-on-and-the-app-terminates-on-swift-markdowns-stack-overflow) | High | Confirmed | Reading view parses a deeply nested Markdown run without the nesting guard while a post-processing plugin is on, and the app terminates on swift-markdown's stack overflow | iPad, iPhone, Mac; only with a community plugin that registers Markdown post-processors and a note nested past swift-markdown's limit (rare  |
| [BUG-CANVAS-01](#bug-canvas-01-undo-while-typing-in-a-text-card-discards-the-typed-text-and-undoes-the-step-before-it) | High | Confirmed | Undo while typing in a text card discards the typed text and undoes the step before it | iPad and iPhone (canvas editing is UIKit-only, WorkspaceCanvas.swift:14-17) |
| [BUG-VOICE-V01](#bug-voice-v01-a-pronunciation-file-that-fails-to-read-or-parse-is-replaced-by-the-one-entry-added-in-settings) | High | Confirmed | A pronunciation file that fails to read or parse is replaced by the one entry added in Settings | iPad, iPhone and Mac |
| [BUG-RUNTIME-01](#bug-runtime-01-a-plugins-asynchronous-edit-lands-in-the-note-the-person-switched-to) | High | Confirmed | A plugin's asynchronous edit lands in the note the person switched to | iPad, iPhone, Mac |
| [BUG-SHELL-01](#bug-shell-01-a-graphiteread-link-whose-file-does-not-resolve-reads-the-note-that-is-already-open-aloud) | Medium | Confirmed | A `graphite://read` link whose file does not resolve reads the note that is already open aloud | iPad, iPhone, Mac |
| [BUG-EDITOR-01](#bug-editor-01-on-the-mac-closing-a-tab-switching-vault-or-leaving-the-app-stores-a-stale-place-for-the-note-on-screen-so-the-reopened-note-does-not-show-where-it-was-left) | Medium | Confirmed | On the Mac, closing a tab, switching vault or leaving the app stores a stale place for the note on screen, so the reopened note does not show where it was left | macOS only; normal path (closing the visible tab, switching vault, the scene leaving `.active`); every time the visible note was scrolled si |
| [BUG-EDITOR-02](#bug-editor-02-on-the-mac-search-current-file-and-search--replace-in-current-file-in-the-command-palette-close-the-palette-and-open-nothing) | Medium | Confirmed | On the Mac, "Search current file" and "Search & replace in current file" in the command palette close the palette and open nothing | macOS only; normal path (command palette, ⌘P); every use. |
| [BUG-EDITOR-04](#bug-editor-04-on-the-mac-switching-from-reading-view-back-to-editing-shows-the-place-the-editor-had-before-not-the-passage-that-was-being-read) | Medium | Confirmed | On the Mac, switching from reading view back to editing shows the place the editor had before, not the passage that was being read | macOS only; normal path whenever the hidden editor was kept (up to three hidden notes, MarkdownEditorRetention.swift:35), which is the usual |
| [BUG-READING-01](#bug-reading-01-a-heading-whose-text-reading-view-rewrites-gets-different-fold-keys-in-reading-view-and-the-editor-so-folds-do-not-carry-between-views-and-read-aloud-reads-a-section-folded-in-reading-view) | Medium | Confirmed | A heading whose text reading view rewrites gets different fold keys in reading view and the editor, so folds do not carry between views and Read Aloud reads a section folded in reading view | iPad, iPhone, Mac; normal path; any heading with a link, highlight, color, closing hashes (`## Title ##`) or repeated spaces after the hashe |
| [BUG-READING-02](#bug-reading-02-a-callout-expanded-or-collapsed-in-reading-view-keeps-a-different-state-in-live-preview-and-in-read-aloud-when-its-title-contains-markup-reading-view-rewrites) | Medium | Confirmed | A callout expanded or collapsed in reading view keeps a different state in Live Preview and in Read Aloud when its title contains markup reading view rewrites | iPad, iPhone, Mac; normal path; foldable callouts whose title has a link, highlight or color. |
| [BUG-READING-03](#bug-reading-03-reading-view-accepts-a-folder-as-the-target-of-a-wikilink-or-embed-so-projects-shows-a-link-to-the-folder-even-when-projectsprojectsmd-exists-and-a-themed-link-to-a-missing-note-is-drawn-as-resolved) | Medium | Confirmed | Reading view accepts a folder as the target of a Wikilink or embed, so `![[Projects]]` shows a link to the folder (even when `Projects/Projects.md` exists) and a themed link to a missing note is drawn as resolved | iPad, iPhone, Mac (and canvas text cards, which use the same builder, CanvasCardViews.swift:191); normal path; any vault with a folder named |
| [BUG-MDCORE-02](#bug-mdcore-02-return-inside-a-fenced-code-block-written-in-a-quote-or-callout-adds-list-markup-to-the-code-or-deletes-the-lines--and-ends-the-callout) | Medium | Confirmed | Return inside a fenced code block written in a quote or callout adds list markup to the code, or deletes the line's `>` and ends the callout | iPad and iPhone (the only caller is the UIKit editor, NativeMarkdownEditor.swift:1394); normal typing with smart lists on; every Return at t |
| [BUG-MDCORE-04](#bug-mdcore-04-setext-headings-are-listed-by-the-index-and-drawn-as-headings-by-the-editor-but-missing-from-the-outline-heading-links-section-embeds-heading-completion-and-folding) | Medium | Confirmed | Setext headings are listed by the index and drawn as headings by the editor, but missing from the outline, heading links, section embeds, heading completion and folding | iPad, iPhone, Mac; normal path for notes written with `Title` / `===` (imported from other editors or converters); every use of those featur |
| [BUG-VAULT-01](#bug-vault-01-renaming-a-file-to-a-name-another-file-shares-except-for-a-non-ascii-capital-rewrites-links-to-a-bare-name-that-then-resolves-to-two-files) | Medium | Confirmed | Renaming a file to a name another file shares except for a non-ASCII capital rewrites links to a bare name that then resolves to two files | iPad, iPhone, Mac; normal rename-with-"Update links" path; rare trigger (two names differing only in the case of a non-ASCII letter: `Éclair |
| [BUG-VAULT-02](#bug-vault-02-a-bookmarksjson-that-graphite-cannot-read-shows-as-no-bookmarks-with-no-error) | Medium | Confirmed | A `bookmarks.json` that Graphite cannot read shows as "no bookmarks", with no error | iPad, iPhone, Mac; fallback path: a file over 1 MiB (rare), or a coordinated read the provider fails (cloud vault offline) |
| [BUG-BASES-03](#bug-bases-03-filehaslinkfilename-leaves-out-matching-notes-when-a-note-of-that-name-sits-at-the-vault-root) | Medium | Confirmed | `file.hasLink(file("Name"))` leaves out matching notes when a note of that name sits at the vault root | iPad, iPhone, Mac |
| [BUG-CANVAS-02](#bug-canvas-02-edits-made-to-an-open-canvas-while-it-or-its-folder-moves-are-lost) | Medium | Confirmed | Edits made to an open canvas while it or its folder moves are lost | iPad and iPhone (editing) |
| [BUG-CANVAS-03](#bug-canvas-03-on-the-mac-the-content-of-a-text-note-or-base-card-longer-than-its-card-cannot-be-scrolled) | Medium | Confirmed | On the Mac, the content of a text, note or base card longer than its card cannot be scrolled | Mac only |
| [BUG-INK-01](#bug-ink-01-a-recovered-drawing-draft-reopens-with-the-original-background-losing-the-paper-colour-the-user-chose) | Medium | Confirmed | A recovered drawing draft reopens with the original background, losing the paper colour the user chose | iPad and iPhone (the draft and recovery code is inside `#if canImport(UIKit)`, GraphiteRootView.swift:171, GraphiteRootView.swift:586) |
| [BUG-INK-02](#bug-ink-02-the-shape-shown-while-holding-the-pencil-is-not-what-the-stroke-becomes-when-the-canvas-is-zoomed) | Medium | Confirmed | The shape shown while holding the Pencil is not what the stroke becomes when the canvas is zoomed | iPad and iPhone (UIKit canvases) |
| [BUG-INK-03](#bug-ink-03-two-quick-taps-on-rotate-image-right-turn-a-drawings-picture-once-and-leave-two-undo-steps) | Medium | Confirmed | Two quick taps on "Rotate Image Right" turn a drawing's picture once and leave two undo steps | iPad and iPhone |
| [BUG-LECTURE-01](#bug-lecture-01-one-lecture-whose-save-failed-is-offered-again-as-a-second-recording-and-can-be-saved-twice) | Medium | Confirmed | One lecture whose save failed is offered again as a second recording and can be saved twice | iPad, iPhone and Mac |
| [BUG-VOICE-01](#bug-voice-01-stop-in-the-floating-player-between-two-pdf-pages-does-not-stop-the-next-page-starts-reading) | Medium | Confirmed | Stop in the floating player between two PDF pages does not stop: the next page starts reading | iPad, iPhone and Mac |
| [BUG-VOICE-03](#bug-voice-03-every-sentence-skip-passage-jump-and-pdf-page-break-gives-up-and-retakes-the-audio-session-contrary-to-the-documented-contract) | Medium | Confirmed | Every sentence skip, passage jump and PDF page break gives up and retakes the audio session, contrary to the documented contract | iPad and iPhone for session deactivation (the `#if os(iOS)` blocks) |
| [BUG-VOICE-04](#bug-voice-04-high-quality-plays-faster-speeds-at-15-while-the-controls-show-the-chosen-speed) | Medium | Confirmed | High Quality plays faster speeds at 1.5× while the controls show the chosen speed | iPad, iPhone and Mac |
| [BUG-VOICE-05](#bug-voice-05-under-voiceover-speak-selection-or-speak-screen-high-quality-reading-has-no-working-speed-control) | Medium | Confirmed | Under VoiceOver, Speak Selection or Speak Screen, High Quality reading has no working speed control | iPad and iPhone (the property is false on the Mac, ReadAloudSpeech.swift:206-211) |
| [BUG-VOICE-07](#bug-voice-07-closing-reading-choosing-quick-deleting-the-voice-or-leaving-the-app-mid-render-keeps-the-neural-model-in-memory) | Medium | Confirmed | Closing reading, choosing Quick, deleting the voice or leaving the app mid-render keeps the neural model in memory | iPad, iPhone and Mac, on devices (the Simulator never loads a model, NeuralSpeechEngine.swift:80-81) |
| [BUG-VOICE-08](#bug-voice-08-unplugging-headphones-during-high-quality-reading-does-not-pause-it) | Medium | Confirmed | Unplugging headphones during High Quality reading does not pause it | iPad and iPhone with wired or Bluetooth outputs |
| [BUG-VOICE-10](#bug-voice-10-editing-any-pronunciation-in-settings-strips-hand-written-ipa-from-the-vaults-pronunciation-file) | Medium | Confirmed | Editing any pronunciation in Settings strips hand-written IPA from the vault's pronunciation file | iPad, iPhone and Mac |
| [BUG-PLUGIN-01](#bug-plugin-01-turning-community-plugins-off-and-on-again-quickly-leaves-them-off-while-the-switch-shows-on) | Medium | Confirmed | Turning community plugins off and on again quickly leaves them off while the switch shows on | iPad, iPhone, Mac |
| [BUG-PLUGIN-02](#bug-plugin-02-a-plugin-whose-onload-never-settles-stops-every-later-plugin-from-loading-and-saved-plugin-views-are-never-restored) | Medium | Confirmed | A plugin whose `onload` never settles stops every later plugin from loading, and saved plugin views are never restored | iPad, iPhone, Mac |
| [BUG-PLUGIN-03](#bug-plugin-03-a-plugins-filemanagerrenamefile-onto-an-existing-name-is-answered-as-a-success-although-nothing-moved) | Medium | Confirmed | A plugin's `fileManager.renameFile` onto an existing name is answered as a success although nothing moved | iPad, iPhone, Mac |
| [BUG-PLUGIN-04](#bug-plugin-04-a-plugins-bases-view-keeps-stale-formula-values-when-results-change-but-rows-do-not) | Medium | Confirmed | A plugin's Bases view keeps stale formula values when results change but rows do not | iPad, iPhone, Mac |
| [BUG-PLUGIN-06](#bug-plugin-06-leaving-a-vault-reloading-plugins-or-turning-them-off-erases-the-vaults-saved-plugin-views) | Medium | Confirmed | Leaving a vault, reloading plugins or turning them off erases the vault's saved plugin views | iPad, iPhone, Mac |
| [BUG-RUNTIME-02](#bug-runtime-02-keyboard-shortcuts-plugins-register-with-mod-never-fire) | Medium | Confirmed | Keyboard shortcuts plugins register with `Mod` never fire | Mac, and iPad and iPhone with a hardware keyboard |
| [BUG-RUNTIME-03](#bug-runtime-03-a-plugin-view-opened-in-the-current-tab-never-appears-and-is-never-closed) | Medium | Confirmed | A plugin view opened "in the current tab" never appears and is never closed | iPad, iPhone, Mac |
| [BUG-ARCH-07](#bug-arch-07-read-aloud-resumes-a-note-at-a-place-remembered-for-a-same-named-note-of-another-vault) | Medium | Confirmed | Read Aloud resumes a note at a place remembered for a same-named note of another vault | All platforms |

## Aliases

| Kept | Alias | Why |
| --- | --- | --- |
| BUG-SHELL-03 | BUG-ARCH-02 | Both describe the Mac quit reply allowing termination after a failed or slow save ([GraphiteMacScenes.swift:51-63](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L51-L63)). |
| BUG-SHELL-02 | BUG-ARCH-06 | Both describe the folded-heading records of a removed vault staying in the device preferences. |

## Third reading by the lead

The lead re-read the code of every High defect and of the two entries with the largest consequence if wrong (the Refuted one and the keychain one), independently of both earlier readers:

| ID | Lead result | What was read |
| --- | --- | --- |
| BUG-CANVAS-01 | Agrees: Confirmed, High. `applyFromHistory` sets `textEdit = nil` without `commitTextEdit()`, and the toolbar Undo reaches it through `UndoAvailability.undo()`. Kept at High, not Critical: Undo is expected to remove recent typing; the loss is that Redo cannot bring the text back. | [CanvasSession.swift:238-244](../../Sources/GraphiteUI/CanvasSession.swift#L238-L244), [279-289](../../Sources/GraphiteUI/CanvasSession.swift#L279-L289), [UndoAvailability.swift:52-56](../../Sources/GraphiteUI/UndoAvailability.swift#L52-L56) |
| BUG-SHELL-03 | Agrees: Confirmed, High. The quit reply allows termination after `try?` swallows the save failure, and again after 5 s. | [GraphiteMacScenes.swift:49-63](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L49-L63), [WorkspaceModel.swift:487-493](../../Sources/GraphiteUI/WorkspaceModel.swift#L487-L493) |
| BUG-VOICE-V01 | Agrees: Confirmed, High. `load` turns a failed read into `[]` and the next add writes the file from it. Found BUG-VOICE-L01 on the same path. | [ReadAloudPronunciationEditor.swift:95-108](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L95-L108), [ReadAloudPronunciations.swift:61-66](../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L61-L66) |
| BUG-MDCORE-01 | Agrees: Confirmed, High. `sections(of:)` parses with `Document(parsing:)` without the `MarkdownNesting.exceedsSafeDepth` guard that every other parse site applies (grep: 2 Markdown and 6 YAML guarded sites). | [NotePreviewDocument.swift:788-794](../../Sources/GraphiteCore/NotePreviewDocument.swift#L788-L794), [MarkdownSemantics.swift:66](../../Sources/GraphiteCore/MarkdownSemantics.swift#L66) |
| BUG-RUNTIME-01 | Agrees: Confirmed, High. `updateEditorSnapshot` keeps the editor object a running command holds and `adoptSnapshot` rewrites its path, snapshot identifier and text to the newly active note. Kept at High: the edit lands in the note now on screen, where it is visible and undoable. | [community-plugin-runtime-workspace.js:758-790](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L758-L790), [163-174](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L163-L174) |
| BUG-RUNTIME-05 | Agrees: Refuted. The navigation delegate cancels `http`, `https` and `mailto` main-frame navigations. | [CommunityPluginWebContent.swift:141-151](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L141-L151) |
| BUG-PLUGIN-05 | Agrees: Plausible, Medium. The read-to-empty path is certain; whether a read fails while the following update succeeds needs a Mac keychain test. | [CommunityPluginSecretStore.swift:40-60](../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L40-L60) |

## Defects by area

Each entry is the verifier's own trace. "Reported" in the severity line is the auditor's wording where it gave one; the area documents hold the original reports.

### SHELL

#### BUG-SHELL-01 A `graphite://read` link whose file does not resolve reads the note that is already open aloud
- **Verdict:** Confirmed
- **Severity:** Medium (reported: none given; "Traced")
- **Reach:** iPad, iPhone, Mac. Normal deep-link path (Shortcuts, browsers), whenever the named file is missing, ambiguous or fails to open while a note is focused.
- **Trigger:** `graphite://read?file=Missing` arrives while a note is open.
- **Path:**
  1. `.onOpenURL` passes the link to `workspace.handle` ([GraphiteRootView.swift:224-226](../../Sources/GraphiteUI/GraphiteRootView.swift#L224-L226)).
  2. `.read(let file)` calls `openLinkedFile(file)` ([WorkspaceDeepLinks.swift:39-40](../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L39-L40)).
  3. `openLinkedFile` polls the index, sets `errorMessage`, and returns `Void` without opening anything ([WorkspaceDeepLinks.swift:76-90](../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L76-L90)).
  4. `handle` checks only the Read Aloud switch ([WorkspaceDeepLinks.swift:41-44](../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L41-L44)). It then takes `markdownSession`, the focused tab's note ([WorkspaceDeepLinks.swift:45](../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L45); [WorkspaceModel.swift:101](../../Sources/GraphiteUI/WorkspaceModel.swift#L101)), and reads it ([WorkspaceDeepLinks.swift:46](../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L46)).
  5. Outcome: an alert says no file matches, and Graphite reads a different note aloud.
- **Minimal fix:** Make `openLinkedFile` return the opened path, or nil. Read only when `markdownSession?.path` equals that path. When it names a PDF, read the `pdfSession` or say why nothing is read.
- **Rule that prevents the class:** outcomes as return values
- **Aliases:** none
- **Verifier notes:** Two more triggers reach the same line. With several matches, `follow` runs a search instead of opening ([WorkspaceModel.swift:705](../../Sources/GraphiteUI/WorkspaceModel.swift#L705)). When the load fails, `open` leaves the old tab focused ([WorkspaceTabs.swift:410-413](../../Sources/GraphiteUI/WorkspaceTabs.swift#L410-L413)). No test exercises `.read` (grep of `Tests/**` and `App/Tests/**`).

#### BUG-SHELL-02 Removing a vault from the list leaves its folded-heading records, which name its notes, in the app's preferences
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Traced")
- **Reach:** iPad, iPhone, Mac. Normal path, each removal of a vault in which a heading was ever folded.
- **Trigger:** "Remove from List" or the swipe action on a vault that is not open ([VaultSwitcher.swift:154-156](../../Sources/GraphiteUI/VaultSwitcher.swift#L154-L156), [213-219](../../Sources/GraphiteUI/VaultSwitcher.swift#L213-L219)).
- **Path:**
  1. `removeFromVaultList` removes the expanded-folder, recent-file and tab-layout keys, and the places ([WorkspaceModel.swift:244-258](../../Sources/GraphiteUI/WorkspaceModel.swift#L244-L258)).
  2. `GraphiteFolds.<uuid>` is built by a `private` helper in another file ([WorkspaceFolds.swift:7-9](../../Sources/GraphiteUI/WorkspaceFolds.swift#L7-L9)). It is not removed. Its value maps note paths to folded keys ([WorkspaceFolds.swift:11-19](../../Sources/GraphiteUI/WorkspaceFolds.swift#L11-L19)).
  3. Reopening the folder makes a new identifier ([WorkspaceModel.swift:253](../../Sources/GraphiteUI/WorkspaceModel.swift#L253)), so the entry is orphaned for good. This contradicts the method's comment ([WorkspaceModel.swift:242-243](../../Sources/GraphiteUI/WorkspaceModel.swift#L242-L243)).
- **Minimal fix:** Add a `static func forgetFolds(ofVault:)` in `WorkspaceFolds.swift`, call it from `removeFromVaultList`, and add the folds prefix to the removal test.
- **Rule that prevents the class:** one owner per persisted key
- **Aliases:** BUG-ARCH-06
- **Verifier notes:** The test pins only three key families ([UiWorkspaceModelFixTests.swift:158](../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L158)), although its doc comment says folds ([UiWorkspaceModelFixTests.swift:151](../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L151)). Read Aloud places (`GraphiteReadAloudPositions`, a global dictionary keyed by vault-relative path, [ReadAloudNavigator.swift:53](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L53)) are not removed either; see BUG-ARCH-07. The data stays on the user's own device, so I rate this Low.

#### BUG-SHELL-03 Quitting on the Mac discards unsaved edits of a note that cannot be saved, without asking
- **Verdict:** Confirmed
- **Severity:** High (reported: none given; "Partly traced")
- **Reach:** Mac only. ⌘Q is the normal quit path, but the loss needs a failing or slow save: a note in conflict with another app's change (common when Obsidian and Graphite share an iCloud vault), a refused write, or a coordinated write slower than 5 s.
- **Trigger:** A note has unsaved text and `hasExternalConflict`, or its save fails or is slow. The person presses ⌘Q.
- **Path:**
  1. `applicationShouldTerminate` returns `.terminateLater` and starts two tasks ([GraphiteMacScenes.swift:51-63](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L51-L63)).
  2. The first runs `try? await workspace.saveOpenDocuments()` and then `reply.allowTermination()` whatever happened ([GraphiteMacScenes.swift:54-57](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L54-L57)). `saveOpenDocuments` tries every tab and throws the first failure ([WorkspaceModel.swift:487-493](../../Sources/GraphiteUI/WorkspaceModel.swift#L487-L493)). A conflicted note throws `.conflict` before writing ([MarkdownSession.swift:153-154](../../Sources/GraphiteUI/MarkdownSession.swift#L153-L154)).
  3. The second task allows termination after `saveDeadline` (5 s), even while a save is still running ([GraphiteMacScenes.swift:49](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L49), [58-61](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L58-L61)).
  4. Nothing else keeps the unsaved text. File recovery copies only the saved text being replaced ([WorkspaceRecovery.swift:16-24](../../Sources/GraphiteUI/WorkspaceRecovery.swift#L16-L24)). `saveSeparateCopy` exists for this state but is not called ([MarkdownSession.swift:223-228](../../Sources/GraphiteUI/MarkdownSession.swift#L223-L228)).
  5. Outcome: the app quits and the text is gone, with no prompt.
- **Minimal fix:** When the save throws, or when the deadline is hit while a save is unfinished, reply `false` (`reply(toApplicationShouldTerminate: false)`) and show the error. Alternatively, write each failing session's text with `saveSeparateCopy` (or into File recovery) before allowing termination.
- **Rule that prevents the class:** unreadable data moved aside, writes report failure
- **Aliases:** BUG-ARCH-02
- **Verifier notes:** One correction to the report. The Mac's scene-phase path does save plugin file views ([GraphiteRootView.swift:498-502](../../Sources/GraphiteUI/GraphiteRootView.swift#L498-L502)); only the quit reply skips them. Even when a scene-phase change arrives, that path only sets an alert ([GraphiteRootView.swift:481-484](../../Sources/GraphiteUI/GraphiteRootView.swift#L481-L484)) and does not hold the quit. No test covers `applicationShouldTerminate`.

#### BUG-SHELL-04 "Reveal current file" from the command palette or a tab's menu neither shows a hidden sidebar nor scrolls to the file
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Traced")
- **Reach:** iPad, iPhone, Mac. Normal path. The command visibly does nothing whenever the sidebar is hidden, scrolled away from the file, or showing a plugin view.
- **Trigger:** "Files: Reveal current file in navigation" in the palette ([WorkspaceCommands.swift:122](../../Sources/GraphiteUI/WorkspaceCommands.swift#L122)), or "Reveal in Sidebar" in a tab's menu ([WorkspacePanes.swift:286-289](../../Sources/GraphiteUI/WorkspacePanes.swift#L286-L289)).
- **Path:**
  1. `revealCurrentFile` writes the panel key, clears `searchQuery` and inserts the parent folders into `expandedFolders`, and does nothing else ([WorkspaceFileManagement.swift:286-294](../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L286-L294)).
  2. The root view shows the sidebar only on a change of `searchFocusRequest` or `sidebarViewRequest` ([GraphiteRootView.swift:213-215](../../Sources/GraphiteUI/GraphiteRootView.swift#L213-L215)). Neither changes here.
  3. The scroll target `fileToReveal` is private sidebar state ([VaultSidebar.swift:61](../../Sources/GraphiteUI/VaultSidebar.swift#L61), [124-134](../../Sources/GraphiteUI/VaultSidebar.swift#L124-L134)). Only the sidebar's own menu sets it, through `scrollToFile` ([VaultSidebar.swift:247](../../Sources/GraphiteUI/VaultSidebar.swift#L247), [471-477](../../Sources/GraphiteUI/VaultSidebar.swift#L471-L477)). The Mac tree reveals only through that binding ([MacFileTree.swift:42-45](../../Sources/GraphiteUI/MacFileTree.swift#L42-L45)).
  4. A chosen plugin sidebar view keeps priority, because `shownSidebarViewIdentifier` is not cleared ([VaultSidebar.swift:81-87](../../Sources/GraphiteUI/VaultSidebar.swift#L81-L87), [265-268](../../Sources/GraphiteUI/VaultSidebar.swift#L265-L268)).
- **Minimal fix:** Make the reveal a workspace request (`revealRequest: VaultPath?`, or a counter like `searchFocusRequest`). The root view answers it by showing the sidebar, and the sidebar answers it by clearing the plugin view and scrolling. All three entry points then call the same path.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** The sidebar's own menu works because it does both halves itself ([VaultSidebar.swift:471-477](../../Sources/GraphiteUI/VaultSidebar.swift#L471-L477)). This is a split implementation of one command. The `@AppStorage` panel does follow the `UserDefaults` write, so the panel does switch to Files.

#### BUG-SHELL-05 File Recovery says "No Snapshots Yet" when its list cannot be read, and spins forever when a snapshot's text cannot be read
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Partly traced")
- **Reach:** iPad, iPhone, Mac. Failure path only. The store lives in the app's container, so read failures are rare: a snapshot removed by pruning or rotation while its preview is open, a non-UTF-8 snapshot, an unreadable directory, or `fileRecovery == nil` because the store failed to open.
- **Trigger:** `recoverableNotes()`, `snapshots(for:)` or `text(of:)` throws, or `workspace.fileRecovery` is nil.
- **Path:**
  1. The note list uses `(try? fileRecovery.recoverableNotes()) ?? []` and then `hasLoaded = true` ([FileRecoverySheet.swift:57-62](../../Sources/GraphiteUI/FileRecoverySheet.swift#L57-L62)), which shows "No Snapshots Yet" ([FileRecoverySheet.swift:25-28](../../Sources/GraphiteUI/FileRecoverySheet.swift#L25-L28)). A nil store does the same ([FileRecoverySheet.swift:59](../../Sources/GraphiteUI/FileRecoverySheet.swift#L59)). It is nil when `try? FileRecoveryStore.forVault` fails ([WorkspaceModel.swift:337](../../Sources/GraphiteUI/WorkspaceModel.swift#L337)).
  2. The snapshot list follows the same pattern ([FileRecoverySheet.swift:98-103](../../Sources/GraphiteUI/FileRecoverySheet.swift#L98-L103)).
  3. The preview uses `try? fileRecovery.text(of:)`, which leaves `text` nil, and returns early when the store is nil ([FileRecoverySheet.swift:142-146](../../Sources/GraphiteUI/FileRecoverySheet.swift#L142-L146)). The overlay shows a `ProgressView` while `text == nil` ([FileRecoverySheet.swift:124](../../Sources/GraphiteUI/FileRecoverySheet.swift#L124)), and Copy and Restore stay disabled ([FileRecoverySheet.swift:128-131](../../Sources/GraphiteUI/FileRecoverySheet.swift#L128-L131)).
  4. `text(of:)` throws on a missing file or non-UTF-8 data ([FileRecovery.swift:79-84](../../Sources/GraphiteCore/FileRecovery.swift#L79-L84)). `recoverableNotes()` throws when the directory listing fails ([FileRecovery.swift:87-94](../../Sources/GraphiteCore/FileRecovery.swift#L87-L94)).
- **Minimal fix:** Load into a three-state value (`loading`, `loaded([…])`, `failed(message)`) and show the error with a Retry button instead of the empty state or the spinner.
- **Rule that prevents the class:** failed reads are never empty results
- **Aliases:** none
- **Verifier notes:** I read the Core throwers that the report left unread. Pruning ([FileRecovery.swift:97-110](../../Sources/GraphiteCore/FileRecovery.swift#L97-L110)) and per-note rotation can remove a listed snapshot before its preview loads, so the spinner state can be reached without any disk fault.

#### BUG-SHELL-06 The phone's tab switcher lists a tab showing a community plugin view as "New Tab"
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Traced")
- **Reach:** iPhone and compact iPad windows with community plugins that open views in tabs. Normal path, cosmetic.
- **Trigger:** A plugin view opens in a tab. The person taps the tabs button in the bottom bar ([GraphiteRootView.swift:386-388](../../Sources/GraphiteUI/GraphiteRootView.swift#L386-L388)).
- **Path:**
  1. `row(for:)` takes the icon from `tab.path` ([TabSwitcher.swift:54](../../Sources/GraphiteUI/TabSwitcher.swift#L54)) and the title from `title(of:)` ([TabSwitcher.swift:59](../../Sources/GraphiteUI/TabSwitcher.swift#L59)).
  2. `title(of:)` returns "New Tab" whenever `tab.path` is nil ([TabSwitcher.swift:102-104](../../Sources/GraphiteUI/TabSwitcher.swift#L102-L104)).
  3. The tab bar's own `title(of:)` names the plugin view ([WorkspacePanes.swift:295-300](../../Sources/GraphiteUI/WorkspacePanes.swift#L295-L300)).
- **Minimal fix:** Move the tab title, including the plugin view case, into one `WorkspaceModel.title(ofTab:)` and use it in both views.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** Same root cause as SHELL-04: two copies of one rule. No disagreement with the report.

### EDITOR

#### BUG-EDITOR-01 On the Mac, closing a tab, switching vault or leaving the app stores a stale place for the note on screen, so the reopened note does not show where it was left
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Mac, normal path")
- **Reach:** macOS only; normal path (closing the visible tab, switching vault, the scene leaving `.active`); every time the visible note was scrolled since it was last shown.
- **Trigger:** On the Mac, open a note, scroll down, close its tab with the note on screen (or open another vault); reopen the note.
- **Path:** `removeTabDocuments` stores places before unloading ([WorkspaceTabs.swift:211](../../Sources/GraphiteUI/WorkspaceTabs.swift#L211), unload at [WorkspaceTabs.swift:215](../../Sources/GraphiteUI/WorkspaceTabs.swift#L215)) → `placeToRemember(of:)` asks the session ([WorkspacePlaces.swift:43](../../Sources/GraphiteUI/WorkspacePlaces.swift#L43)) → `MarkdownSession.placeToRemember` calls `recordEditorPlace?()` and then reads `savedScrollLocation` ([MarkdownSession.swift:69-80](../../Sources/GraphiteUI/MarkdownSession.swift#L69-L80)) → `recordEditorPlace` is assigned only by the iPad coordinator's `reportPlace` ([NativeMarkdownEditor.swift:1014-1019](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L1014-L1019)); the Mac coordinator (from [NativeMarkdownEditor.swift:2327](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2327)) never assigns it, so the call is a no-op → on the Mac, `savedScrollLocation` is written only by `recordScrollLocation` ([NativeMarkdownEditor.swift:3506-3515](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L3506-L3515)), called only from `suspend` ([NativeMarkdownEditor.swift:2962](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2962)), which runs when the SwiftUI view is dismantled ([NativeMarkdownEditor.swift:2944-2953](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2944-L2953)), after the place was stored and after the tab document was dropped → the stored top location is the one set when the note opened (`returnTo`, [MarkdownSession.swift:86-89](../../Sources/GraphiteUI/MarkdownSession.swift#L86-L89)) or at the last suspend. The same stale read happens on vault switch ([WorkspaceModel.swift:263](../../Sources/GraphiteUI/WorkspaceModel.swift#L263)) and when the scene leaves `.active` ([GraphiteRootView.swift:227-231](../../Sources/GraphiteUI/GraphiteRootView.swift#L227-L231)).
- **Minimal fix:** Have the Mac coordinator set `session.recordEditorPlace` in `resume`/`makeScrollView` to call `recordScrollLocation(of:)` (guarded by `pendingJump == nil`), and clear it in `suspend`, as the iPad does.
- **Rule that prevents the class:** contract test suites shared by every implementation
- **Aliases:** none
- **Verifier notes:** No test in `Tests/**` or `App/Tests/**` touches `placeToRemember` or `recordEditorPlace` (grep empty). When the user switched tabs before closing, the earlier dismantle already recorded a correct place; the defect hits the tab that is on screen at close time, which is the usual case. The cursor is restored correctly ([MarkdownSession.swift:92-93](../../Sources/GraphiteUI/MarkdownSession.swift#L92-L93)), so after reopening the selection and the scroll position disagree. Whether macOS moves `scenePhase` out of `.active` at quit is runtime behaviour; the tab-close and vault-switch paths settle the verdict without it.

#### BUG-EDITOR-02 On the Mac, "Search current file" and "Search & replace in current file" in the command palette close the palette and open nothing
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Mac, normal path")
- **Reach:** macOS only; normal path (command palette, ⌘P); every use.
- **Trigger:** On the Mac, with a Markdown note focused, open the command palette and run either command.
- **Path:** the palette overlay is compiled on every platform ([GraphiteRootView.swift:103](../../Sources/GraphiteUI/GraphiteRootView.swift#L103), [GraphiteRootView.swift:400-413](../../Sources/GraphiteUI/GraphiteRootView.swift#L400-L413)) and lists `noteCommands` whenever a note is focused ([WorkspaceCommands.swift:130-131](../../Sources/GraphiteUI/WorkspaceCommands.swift#L130-L131)) → the two commands call `session.requestFind` ([WorkspaceCommands.swift:218-223](../../Sources/GraphiteUI/WorkspaceCommands.swift#L218-L223)) → which leaves reading view and sets `findRequest` ([MarkdownSession.swift:449-452](../../Sources/GraphiteUI/MarkdownSession.swift#L449-L452)) → the only reader is the iPad's `presentFindIfRequested` ([NativeMarkdownEditor.swift:1218-1225](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L1218-L1225)); the Mac `update` reads no `findRequest` ([NativeMarkdownEditor.swift:2792-2838](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2792-L2838)) and no Mac code enables a find bar (grep `usesFindBar|NSTextFinder|performFindPanelAction` over `Sources/**` finds nothing) → nothing appears; `findRequest` stays set.
- **Minimal fix:** Read `session.findRequest` in the Mac `update`, set `textView.usesFindBar = true` when the view is made, and call `performTextFinderAction` with `.showFindInterface` or `.showReplaceInterface`, then clear the request.
- **Rule that prevents the class:** contract test suites shared by every implementation
- **Aliases:** none
- **Verifier notes:** I read the palette's presentation that the report left open: `paletteOverlay` has no platform condition. From reading view the command only switches to editing. The shortcut labels "⌘F"/"⌥⌘F" shown in the palette have no Mac menu item behind them either (grep for a Find menu command in `GraphiteCommands.swift` finds none), so the label promises a shortcut that does nothing.

#### BUG-EDITOR-03 On the Mac, a note created with New Note is not ready to type, and its "start editing" flag stays set
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "Mac, normal path")
- **Reach:** macOS only; normal path; every note created in Graphite.
- **Trigger:** On the Mac, create a note (⌘N or the palette's "Create new note").
- **Path:** `createNote` opens the note and sets `startsEditingWhenShown = true` ([WorkspaceModel.swift:721-723](../../Sources/GraphiteUI/WorkspaceModel.swift#L721-L723)) → the flag is observed ([MarkdownSession.swift:98-100](../../Sources/GraphiteUI/MarkdownSession.swift#L98-L100)) but read and cleared only by the iPad's `startEditingIfRequested` ([NativeMarkdownEditor.swift:1193-1201](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L1193-L1201)); grep `startsEditingWhenShown` finds no Mac reader → the Mac text view becomes first responder only on a click or through "Edit Source"/block reveal ([NativeMarkdownEditor.swift:3292](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L3292), [NativeMarkdownEditor.swift:3303](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L3303)) → the new note is not focused.
- **Minimal fix:** In the Mac `update`, when `session.startsEditingWhenShown` is true and the view has a window, clear the flag and call `makeFirstResponder(textView)` on the next main-queue turn.
- **Rule that prevents the class:** contract test suites shared by every implementation
- **Aliases:** none
- **Verifier notes:** A single click recovers it, so I rate it Low rather than the Medium the effect suggests. The flag left `true` has no other reader, so it causes no later surprise.

#### BUG-EDITOR-04 On the Mac, switching from reading view back to editing shows the place the editor had before, not the passage that was being read
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Mac, normal path")
- **Reach:** macOS only; normal path whenever the hidden editor was kept (up to three hidden notes, [MarkdownEditorRetention.swift:35](../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L35)), which is the usual case for ⌘E back and forth.
- **Trigger:** On the Mac, open a note in Live Preview, switch to reading view, scroll to another passage, switch back to editing.
- **Path:** leaving reading view stores the reading view's top line in `savedScrollLocation` and `pendingEditingLocation` ([MarkdownSession.swift:24-35](../../Sources/GraphiteUI/MarkdownSession.swift#L24-L35)) → the pane shows `NativeMarkdownEditor` again ([MarkdownPane.swift:82-85](../../Sources/GraphiteUI/MarkdownPane.swift#L82-L85)) → `makeCoordinator` takes the kept editor ([NativeMarkdownEditor.swift:2725-2728](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2725-L2728); the editor was kept on dismantle, [MarkdownEditorRetention.swift:107-119](../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L107-L119), and is returned at [MarkdownEditorRetention.swift:86-92](../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L86-L92)) → `makeNSView` skips `makeScrollView` because `scrollView` is kept ([NativeMarkdownEditor.swift:2737-2741](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2737-L2741)); `makeScrollView` is the only Mac place that turns `savedScrollLocation` into a jump ([NativeMarkdownEditor.swift:2773](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2773)) → `viewWasMade` → `resume` sets no jump ([NativeMarkdownEditor.swift:2933-2939](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2933-L2939), [NativeMarkdownEditor.swift:2968-2972](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2968-L2972)) → `update` performs only a pending jump, of which there is none ([NativeMarkdownEditor.swift:2836](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2836)); `takeEditingStartLocation` ([MarkdownSession.swift:52-55](../../Sources/GraphiteUI/MarkdownSession.swift#L52-L55)) has only the iPad caller ([NativeMarkdownEditor.swift:1203-1215](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L1203-L1215)) → the kept scroll view shows its old position.
- **Minimal fix:** In the Mac `resume` (or `update`), take `session.takeEditingStartLocation()` and set `pendingJump = .topOfCharacter(location)` (scroll to top for 0), as the iPad's `goToReadingPlaceIfSwitched` does.
- **Rule that prevents the class:** contract test suites shared by every implementation
- **Aliases:** none
- **Verifier notes:** The Mac tests pin jumps only for headings ([UiEditorMacEditorTests.swift:375-389](../../Tests/GraphiteUITests/UiEditorMacEditorTests.swift#L375-L389)); none pins the reading-to-editing return. When the editor was not kept (budget exceeded, first switch after a memory purge), `makeScrollView` runs and the jump lands, so the defect shows on the common path and not on the rare one.

### READING

#### BUG-READING-01 A heading whose text reading view rewrites gets different fold keys in reading view and the editor, so folds do not carry between views and Read Aloud reads a section folded in reading view
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "normal path")
- **Reach:** iPad, iPhone, Mac; normal path; any heading with a link, highlight, color, closing hashes (`## Title ##`) or repeated spaces after the hashes.
- **Trigger:** Fold such a heading in Live Preview (or Fold All) and switch to reading view; or fold it in reading view, then start Read Aloud or switch to editing.
- **Path:** one fold set serves both views ([MarkdownPane.swift:68-70](../../Sources/GraphiteUI/MarkdownPane.swift#L68-L70)) → the editor and Fold All key a heading by its trimmed source line ([NoteFolding.swift:62](../../Sources/GraphiteCore/NoteFolding.swift#L62), [MarkdownSession.swift:306-308](../../Sources/GraphiteUI/MarkdownSession.swift#L306-L308)), e.g. `h2|## Title ##|0` → reading view's heading text is regex group 2 without the closing sequence and without extra spaces ([NotePreviewDocument.swift:30](../../Sources/GraphiteCore/NotePreviewDocument.swift#L30), [NotePreviewDocument.swift:154-156](../../Sources/GraphiteCore/NotePreviewDocument.swift#L154-L156)), then rewritten by `prepared` ([MarkdownPreview.swift:406](../../Sources/GraphiteUI/MarkdownPreview.swift#L406); Wikilinks at [MarkdownPreview.swift:553-560](../../Sources/GraphiteUI/MarkdownPreview.swift#L553-L560), highlights into markers at [MarkdownPreview.swift:571-573](../../Sources/GraphiteUI/MarkdownPreview.swift#L571-L573)) → reading view builds its key from that text ([MarkdownPreview.swift:1365-1371](../../Sources/GraphiteUI/MarkdownPreview.swift#L1365-L1371)): `h2|## Title|0` → the keys differ, so `visibleBlocks` shows a section the editor folded ([MarkdownPreview.swift:1383](../../Sources/GraphiteUI/MarkdownPreview.swift#L1383)), and a fold made in reading view inserts a key ([MarkdownPreview.swift:1421-1423](../../Sources/GraphiteUI/MarkdownPreview.swift#L1421-L1423)) that no `NoteFolding` region has → Read Aloud hides only `NoteFolding` regions whose key is in the set ([MarkdownPane.swift:602-605](../../Sources/GraphiteUI/MarkdownPane.swift#L602-L605), [ReadAloudFolding.swift:17](../../Sources/GraphiteCore/ReadAloudFolding.swift#L17)) → the section folded in reading view is read aloud; a heading jump unfolds only `NoteFolding` regions ([MarkdownSession.swift:301-303](../../Sources/GraphiteUI/MarkdownSession.swift#L301-L303)), so a target inside a reading-view fold stays hidden.
- **Minimal fix:** Carry the `NoteFolding` key in the reading-view heading block (computed from the source line when the block is located), instead of rebuilding it from the rendered text.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** For a plain `## Title` the two keys agree, which is why the existing `NoteFoldingTests` pass; no test compares the two key builders. Reading view drops headings inside `%%` comments before numbering ([NotePreviewDocument.swift:75-80](../../Sources/GraphiteCore/NotePreviewDocument.swift#L75-L80)) and `NoteFolding` does not, so occurrence numbers can shift too. Orphan keys do no harm in the editor, because `foldedRegions` filters by existing regions.

#### BUG-READING-02 A callout expanded or collapsed in reading view keeps a different state in Live Preview and in Read Aloud when its title contains markup reading view rewrites
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "normal path for callouts whose title contains markup")
- **Reach:** iPad, iPhone, Mac; normal path; foldable callouts whose title has a link, highlight or color.
- **Trigger:** `> [!note]- See [[Plan]]`: expand it in reading view, then press Read Document or switch to Live Preview.
- **Path:** reading view prepares the title and stores the prepared text in the block ([MarkdownPreview.swift:408-414](../../Sources/GraphiteUI/MarkdownPreview.swift#L408-L414)) → `ReadingCallout` passes it to `CalloutView` without `foldKeyTitle` ([MarkdownPreview.swift:1440-1441](../../Sources/GraphiteUI/MarkdownPreview.swift#L1440-L1441), [MarkdownPreview.swift:1533-1536](../../Sources/GraphiteUI/MarkdownPreview.swift#L1533-L1536)), so the key title falls back to the prepared title ([MarkdownPreview.swift:2470](../../Sources/GraphiteUI/MarkdownPreview.swift#L2470)) → the expansion is stored under `note|<prepared title>` in the shared store ([MarkdownPreview.swift:2447-2450](../../Sources/GraphiteUI/MarkdownPreview.swift#L2447-L2450), [CalloutFoldStore.swift:18-20](../../Sources/GraphiteUI/CalloutFoldStore.swift#L18-L20); the store reaches reading view through [MarkdownPane.swift:131](../../Sources/GraphiteUI/MarkdownPane.swift#L131)) → Live Preview keys the callout by the written title ([LivePreviewWidgets.swift:272-277](../../Sources/GraphiteUI/LivePreviewWidgets.swift#L272-L277)) and Read Aloud by the written header title ([ReadAloudFolding.swift:43-44](../../Sources/GraphiteCore/ReadAloudFolding.swift#L43-L44)) → neither finds the entry and both fall back to the `-` marker ([CalloutFoldStore.swift:14-16](../../Sources/GraphiteUI/CalloutFoldStore.swift#L14-L16), [ReadAloudFolding.swift:44](../../Sources/GraphiteCore/ReadAloudFolding.swift#L44)) → collapsed.
- **Minimal fix:** Keep the written title in the reading-view callout block and pass it as `foldKeyTitle` from `ReadingCallout`.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none (same class as BUG-READING-01, different key and different code)
- **Verifier notes:** `ReadAloudFolding.calloutKey`'s own comment says the key is "the same for the reading view and Live Preview" ([ReadAloudFolding.swift:8-12](../../Sources/GraphiteCore/ReadAloudFolding.swift#L8-L12)); reading view breaks that promise. A title without markup prepares to itself, so plain callouts work.

#### BUG-READING-03 Reading view accepts a folder as the target of a Wikilink or embed, so `![[Projects]]` shows a link to the folder (even when `Projects/Projects.md` exists) and a themed link to a missing note is drawn as resolved
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "vaults with a note link named like a folder")
- **Reach:** iPad, iPhone, Mac (and canvas text cards, which use the same builder, [CanvasCardViews.swift:191](../../Sources/GraphiteUI/CanvasCardViews.swift#L191)); normal path; any vault with a folder named like a linked note beside the note or at the root, including the common folder-note layout.
- **Trigger:** A note at the root contains `![[Projects]]` or `[[Projects]]`; a folder `Projects` exists at the root.
- **Path:** `directCandidates` yields `Projects.md` then `Projects`, beside the note and from the root ([MarkdownSemantics.swift:873-875](../../Sources/GraphiteCore/MarkdownSemantics.swift#L873-L875), [MarkdownSemantics.swift:898-901](../../Sources/GraphiteCore/MarkdownSemantics.swift#L898-L901)) → the builder's `resolve` accepts any existing path, folders included, before asking the index ([MarkdownPreview.swift:488-494](../../Sources/GraphiteUI/MarkdownPreview.swift#L488-L494)); the workspace resolver refuses folders ([WorkspaceModel.swift:656-659](../../Sources/GraphiteUI/WorkspaceModel.swift#L656-L659)) and Live Preview uses it ([MarkdownPane.swift:344](../../Sources/GraphiteUI/MarkdownPane.swift#L344)) → embed: `renderEmbed` gets the folder ([MarkdownPreview.swift:442](../../Sources/GraphiteUI/MarkdownPreview.swift#L442)), `DocumentKind` of an extensionless path is `.other` ([VaultPath.swift:169](../../Sources/GraphiteCore/VaultPath.swift#L169)), so the `default:` branch re-prepares `![[Projects]]` ([MarkdownPreview.swift:476-478](../../Sources/GraphiteUI/MarkdownPreview.swift#L476-L478)), which resolves the folder again and writes a link to it ([MarkdownPreview.swift:535](../../Sources/GraphiteUI/MarkdownPreview.swift#L535), [MarkdownPreview.swift:542-548](../../Sources/GraphiteUI/MarkdownPreview.swift#L542-L548)) → link with a vault theme: `resolve(...) == nil` is false for the folder ([MarkdownPreview.swift:556-558](../../Sources/GraphiteUI/MarkdownPreview.swift#L556-L558)), so the link is drawn as resolved.
- **Minimal fix:** In `ReadingViewBuilder.resolve`, accept a direct candidate only when it exists and is not a directory, as `WorkspaceModel.resolveLink` does; better, have the builder call one shared resolver.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** The report covers only the "no `Projects.md`" case. I add the folder-note layout: with `Projects/Projects.md` and a root folder `Projects`, the direct candidate `Projects` (the folder) is found before the index lookup that would return `Projects/Projects.md`, so reading view shows a link to the folder instead of embedding the existing note, while Live Preview embeds the note. That makes the defect visible in common vaults, hence Medium. Tapping the folder link reaches `follow`, whose resolver refuses folders ([WorkspaceModel.swift:676](../../Sources/GraphiteUI/WorkspaceModel.swift#L676)), and the index lookup or note creation follows.

#### BUG-READING-04 "Link" on an unlinked mention removes the line from the list even when the link was not written
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "failure path only")
- **Reach:** iPad, iPhone, Mac; failure path only (mentioning note changed since listing, save failed, or no store).
- **Trigger:** In Backlinks › Unlinked mentions, tap Link after the mentioning note changed in another app or tab.
- **Path:** the view awaits `workspace.linkMention` and then filters the match out unconditionally ([MarkdownPane.swift:1030-1039](../../Sources/GraphiteUI/MarkdownPane.swift#L1030-L1039)) → `linkMention` returns `Void` ([WorkspaceMentions.swift:61](../../Sources/GraphiteUI/WorkspaceMentions.swift#L61)); a changed note throws `mentionChanged` ([WorkspaceMentions.swift:71](../../Sources/GraphiteUI/WorkspaceMentions.swift#L71), [WorkspaceMentions.swift:78](../../Sources/GraphiteUI/WorkspaceMentions.swift#L78)), a failed save throws from the store ([WorkspaceMentions.swift:82](../../Sources/GraphiteUI/WorkspaceMentions.swift#L82)), and both become `errorMessage` ([WorkspaceMentions.swift:84](../../Sources/GraphiteUI/WorkspaceMentions.swift#L84)); a missing store returns silently ([WorkspaceMentions.swift:62](../../Sources/GraphiteUI/WorkspaceMentions.swift#L62)) → the alert says nothing was linked while the line leaves the list until the panel reloads ([MarkdownPane.swift:989](../../Sources/GraphiteUI/MarkdownPane.swift#L989)).
- **Minimal fix:** Make `linkMention` return a `Bool` (or a result enum) and remove the line only on success.
- **Rule that prevents the class:** outcomes as return values
- **Aliases:** none
- **Verifier notes:** No data is lost and the alert is shown; the list is only misleading until reload.

#### BUG-READING-05 The same Wikilink reads differently in reading view and in Live Preview's rendered blocks
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "normal path in Live Preview's rendered blocks")
- **Reach:** iPad, iPhone, Mac; normal path; Wikilinks with a heading, block or `.md` in tables, callout titles and bodies drawn by Live Preview.
- **Trigger:** A Live Preview table cell with `[[Lecture 3#Proof]]`, `[[Note.md]]` or `[[Note#^block]]`.
- **Path:** reading view labels Wikilinks with `displayText(for:)` ([MarkdownPreview.swift:560](../../Sources/GraphiteUI/MarkdownPreview.swift#L560), [MarkdownPreview.swift:626-633](../../Sources/GraphiteUI/MarkdownPreview.swift#L626-L633)): `Lecture 3 > Proof`, `Note`, `Note > block` → Live Preview's rendered blocks go through `LivePreviewText.prepared` ([LivePreviewWidgets.swift:272](../../Sources/GraphiteUI/LivePreviewWidgets.swift#L272), [LivePreviewWidgets.swift:376](../../Sources/GraphiteUI/LivePreviewWidgets.swift#L376)), which labels with `alias ?? target` minus a leading `#` only ([LivePreviewWidgets.swift:444](../../Sources/GraphiteUI/LivePreviewWidgets.swift#L444)): `Lecture 3#Proof`, `Note.md`, `Note#^block`.
- **Minimal fix:** Build the Live Preview label with `ReadingViewBuilder.displayText(for:)` (or a shared function taking target and alias).
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** Cosmetic; the destination is the same in both, so following the link works.

### MDCORE

#### BUG-MDCORE-01 Reading view parses a deeply nested Markdown run without the nesting guard while a post-processing plugin is on, and the app terminates on swift-markdown's stack overflow
- **Verdict:** Confirmed (the crash depth is the project's own measurement, not re-measured)
- **Severity:** High  (reported: none given; "only while a post-processing community plugin is on")
- **Reach:** iPad, iPhone, Mac; only with a community plugin that registers Markdown post-processors and a note nested past swift-markdown's limit (rare input, typically synced or generated). The crash repeats each time the note is shown in reading view, including at launch when the last document reopens.
- **Trigger:** A note with a run of two or more Markdown lines, no reference definitions, and a line nested about 55 lists or 64 quotes deep, opened in reading view with such a plugin enabled. The same happens when another note embeds that note (`![[Deep]]`).
- **Path:** the pane passes `runsPluginPostProcessors` ([MarkdownPane.swift:207](../../Sources/GraphiteUI/MarkdownPane.swift#L207)) → `ReadingViewBuilder` is an actor ([MarkdownPreview.swift:259](../../Sources/GraphiteUI/MarkdownPreview.swift#L259)), so `build` runs on a Swift-concurrency thread with the 512 KB stack → `build` calls `sectioned` before `render` ([MarkdownPreview.swift:294-295](../../Sources/GraphiteUI/MarkdownPreview.swift#L294-L295)) → `dividedIntoSections` when plugins post-process ([MarkdownPreview.swift:365-367](../../Sources/GraphiteUI/MarkdownPreview.swift#L365-L367), [NotePreviewDocument.swift:773-777](../../Sources/GraphiteCore/NotePreviewDocument.swift#L773-L777)) → `sections(of:)` calls `Document(parsing: markdown)` with no `MarkdownNesting` check ([NotePreviewDocument.swift:788-794](../../Sources/GraphiteCore/NotePreviewDocument.swift#L788-L794)); deep `>`/list lines are not callouts or headings, so `blocks(fromLines:)` keeps them in a Markdown run ([NotePreviewDocument.swift:192](../../Sources/GraphiteCore/NotePreviewDocument.swift#L192), [NotePreviewDocument.swift:101-104](../../Sources/GraphiteCore/NotePreviewDocument.swift#L101-L104)) → the guard in `ObsidianMarkdownParser` runs only later, inside `render` ([MarkdownPreview.swift:1830](../../Sources/GraphiteUI/MarkdownPreview.swift#L1830)) → swift-markdown converts recursively and crashes at 55 nested lists or 64 nested quotes on that stack ([ParserNestingLimits.swift:3-8](../../Sources/GraphiteCore/ParserNestingLimits.swift#L3-L8)). Embeds go through the same `sectioned` call ([MarkdownPreview.swift:469-471](../../Sources/GraphiteUI/MarkdownPreview.swift#L469-L471)).
- **Minimal fix:** In `sections(of:)`, return `[located]` when `MarkdownNesting.exceedsSafeDepth(markdown)` is true, before `Document(parsing:)`.
- **Rule that prevents the class:** bounded parsing of untrusted input
- **Aliases:** none
- **Verifier notes:** grep `MarkdownNesting` shows the guard at every other parse site (`MarkdownSemantics.swift:66`, `ReadAloudSection.swift:15`, `ReadAloudDocument.swift:303`, `MarkdownPreview.swift:1830`) and not here. The only tests of `dividedIntoSections` use shallow notes ([NotePreviewDocumentTests.swift:62-72](../../Tests/GraphiteCoreTests/NotePreviewDocumentTests.swift#L62-L72)); `CrashLoopRegressionTests` does not cover it. I add the embed path and the actor-thread fact, which makes the project's 512 KB measurement the relevant one. High rather than Critical: no data is lost, and the input is rare.

#### BUG-MDCORE-02 Return inside a fenced code block written in a quote or callout adds list markup to the code, or deletes the line's `>` and ends the callout
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "normal typing path")
- **Reach:** iPad and iPhone (the only caller is the UIKit editor, [NativeMarkdownEditor.swift:1394](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L1394)); normal typing with smart lists on; every Return at the end of a `> - …` line or on an empty `> ` line inside a quoted fence. Undo recovers it.
- **Trigger:** Inside `> ```` ` … `> ```` ` (a callout holding a YAML or Markdown sample), press Return at the end of `> - item`, or on an empty `> ` code line.
- **Path:** Return → `MarkdownEditing.continuingList` ([NativeMarkdownEditor.swift:1394](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L1394)) → `listLine` reads the quote prefix and the marker ([MarkdownEditing.swift:87](../../Sources/GraphiteCore/MarkdownEditing.swift#L87), [MarkdownEditing.swift:92-113](../../Sources/GraphiteCore/MarkdownEditing.swift#L92-L113)) → `isInCodeOrFrontmatter` skips every line whose first non-blank unit is not a backtick or tilde ([MarkdownEditing.swift:216-217](../../Sources/GraphiteCore/MarkdownEditing.swift#L216-L217)); `> ```` ` starts with `>`, so the fence never opens and the function returns false ([MarkdownEditing.swift:220](../../Sources/GraphiteCore/MarkdownEditing.swift#L220)) → the guard at [MarkdownEditing.swift:139](../../Sources/GraphiteCore/MarkdownEditing.swift#L139) passes → for `> - item` the continuation `\n> - ` is inserted ([MarkdownEditing.swift:174-180](../../Sources/GraphiteCore/MarkdownEditing.swift#L174-L180)); for an empty `> ` line the quote marker is replaced by nothing ([MarkdownEditing.swift:167-169](../../Sources/GraphiteCore/MarkdownEditing.swift#L167-L169)), which ends the quote, the callout and its code block at that line.
- **Minimal fix:** In `isInCodeOrFrontmatter`, strip leading quote markers before the first-character test and track fences per quote depth, as `MarkdownStyleScanner.quoteMarkersAndContent` does ([MarkdownStyleScanner.swift:368-376](../../Sources/GraphiteCore/MarkdownStyleScanner.swift#L368-L376)).
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** The function's own contract says Return in code is a plain line break ([MarkdownEditing.swift:124-125](../../Sources/GraphiteCore/MarkdownEditing.swift#L124-L125)). Several other code paths are tested to treat `> ```` ` as a fence (link completion, [CoreLinksFixTests.swift:154-156](../../Tests/GraphiteCoreTests/CoreLinksFixTests.swift#L154-L156); colors, [CoreHtmlColorsTextColorMarkupTests.swift:63-71](../../Tests/GraphiteCoreTests/CoreHtmlColorsTextColorMarkupTests.swift#L63-L71)); `continuingList` has no such test. The empty-`> ` case is the more frequent one: adding a blank line inside quoted code is ordinary typing.

#### BUG-MDCORE-03 A fence line indented four or more columns opens a code block in the editor, reading view and Live Preview, while the index (CommonMark) treats it as text
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "edge-case input on the normal path")
- **Reach:** iPad, iPhone, Mac; edge-case input (a top-level line of 4+ spaces then ```` ``` ````: inside an indented code sample or as a lazy paragraph continuation, with no closing fence nearby).
- **Trigger:** A note containing `    ```` ` outside a list item, followed by headings, callouts or math.
- **Path:** editor: the chunked walk treats leading whitespace as transparent ([MarkdownStyleScanner.swift:287-289](../../Sources/GraphiteCore/MarkdownStyleScanner.swift#L287-L289)) and `nextState` tests the trimmed content ([MarkdownStyleScanner.swift:323-326](../../Sources/GraphiteCore/MarkdownStyleScanner.swift#L323-L326), trim at [MarkdownStyleScanner.swift:369](../../Sources/GraphiteCore/MarkdownStyleScanner.swift#L369)) → following lines get `.codeBlock` spans ([MarkdownStyleScanner.swift:434-438](../../Sources/GraphiteCore/MarkdownStyleScanner.swift#L434-L438)). Reading view: `blocks(fromLines:)` trims before `CodeFence.opening` ([NotePreviewDocument.swift:112-117](../../Sources/GraphiteCore/NotePreviewDocument.swift#L112-L117)) and folds everything to the closing fence into one Markdown run ([NotePreviewDocument.swift:129-133](../../Sources/GraphiteCore/NotePreviewDocument.swift#L129-L133)), so headings in it get no heading block. Live Preview: the block scanner jumps to the closing fence ([LivePreviewBlocks.swift:60-82](../../Sources/GraphiteCore/LivePreviewBlocks.swift#L60-L82)). Index: `MarkdownCodeRanges` applies the three-column limit ([MarkdownSemantics.swift:692-717](../../Sources/GraphiteCore/MarkdownSemantics.swift#L692-L717)) → the four views disagree on the same lines.
- **Minimal fix:** Give `CodeFence` one `opening(line:containerIndentation:)` that refuses more than three columns of indentation outside a list item, and use it in the style scanner, the reading-view splitter and the Live Preview scanner.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** `CodeFence.opening` takes an already trimmed line ([MarkdownSemantics.swift:665-672](../../Sources/GraphiteCore/MarkdownSemantics.swift#L665-L672)), so each caller decides indentation itself; only `MarkdownCodeRanges` does. Inside list items all four agree (the index allows the item's content column). Low: rare input, and editing the line recovers it.

#### BUG-MDCORE-04 Setext headings are listed by the index and drawn as headings by the editor, but missing from the outline, heading links, section embeds, heading completion and folding
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "normal path for notes that use setext headings")
- **Reach:** iPad, iPhone, Mac; normal path for notes written with `Title` / `===` (imported from other editors or converters); every use of those features on such a note.
- **Trigger:** A note with `Title` over `=====` or `-----`; open the Outline, follow `[[Note#Title]]`, embed `![[Note#Title]]`, ask for heading completion, or try to fold it.
- **Path:** the index stores swift-markdown headings, setext included ([MarkdownSemantics.swift:98](../../Sources/GraphiteCore/MarkdownSemantics.swift#L98) → [VaultIndex.swift:350](../../Sources/GraphiteIndex/VaultIndex.swift#L350); the first becomes the title, [VaultIndex.swift:323](../../Sources/GraphiteIndex/VaultIndex.swift#L323)); the editor styles it as a heading ([MarkdownStyleScanner.swift:168-177](../../Sources/GraphiteCore/MarkdownStyleScanner.swift#L168-L177), [MarkdownStyleScanner.swift:472-473](../../Sources/GraphiteCore/MarkdownStyleScanner.swift#L472-L473)) → the outline and sections use `headingLines` → `heading(in:)`, whose pattern is ATX only ([NotePreviewDocument.swift:30](../../Sources/GraphiteCore/NotePreviewDocument.swift#L30), [NotePreviewDocument.swift:295-301](../../Sources/GraphiteCore/NotePreviewDocument.swift#L295-L301), [NotePreviewDocument.swift:222-236](../../Sources/GraphiteCore/NotePreviewDocument.swift#L222-L236)) → section embeds go through `locatedEmbeddedPart` → `locatedSectionIfPresent`, which returns nil ([NoteBlocks.swift:255-261](../../Sources/GraphiteCore/NoteBlocks.swift#L255-L261)), so reading view shows the missing-section block ([MarkdownPreview.swift:464-466](../../Sources/GraphiteUI/MarkdownPreview.swift#L464-L466)) → reading view gives heading blocks with anchors only to ATX lines ([NotePreviewDocument.swift:154-158](../../Sources/GraphiteCore/NotePreviewDocument.swift#L154-L158)) → folding asks `headingLevel`, ATX only ([NoteFolding.swift:91-94](../../Sources/GraphiteCore/NoteFolding.swift#L91-L94), [MarkdownEditing.swift:19](../../Sources/GraphiteCore/MarkdownEditing.swift#L19), [MarkdownEditing.swift:53-56](../../Sources/GraphiteCore/MarkdownEditing.swift#L53-L56)).
- **Minimal fix:** Teach `NotePreviewDocument.headingLines` (and the folding level lookup) to recognise a paragraph line followed by a setext underline, reusing `MarkdownStyleScanner.setextUnderlineLevel` and `isParagraphText`.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** No test pins the omission: the setext tests cover styling and insertion only (`CoreSemanticsEditorScanningTests.swift:71`, `SettingsAndAttachmentTests.swift:205`). Obsidian's own behaviour is outside the snapshot, but the disagreement between Graphite's index and editor on one side and its outline, embeds and folds on the other is traced end to end, and that settles the verdict.

#### BUG-MDCORE-05 Nested alignment environments recurse without a depth limit and rescan the rest of the formula at every level while a display formula is prepared
- **Verdict:** Plausible (the unbounded recursion and the quadratic rescans are confirmed by reading; whether it overflows the stack depends on frame size)
- **Severity:** Medium  (reported: none given; "crafted or generated input only")
- **Reach:** iPad, iPhone, Mac; crafted or generated LaTeX in a synced note; reading view (actor thread, 512 KB stack) and Live Preview math views.
- **Trigger:** A display formula with thousands of nested `\begin{aligned}…\end{aligned}`.
- **Path:** reading view `readingText` → `preparedForReading` ([MarkdownPreview.swift:571-573](../../Sources/GraphiteUI/MarkdownPreview.swift#L571-L573), [NotePreviewDocument.swift:365-375](../../Sources/GraphiteCore/NotePreviewDocument.swift#L365-L375)) → `protectingMathKeepingLineIndices` → `joinedDisplayMath` → `displayMath` → `LaTeXCompatibility.normalized` ([NotePreviewDocument.swift:540-606](../../Sources/GraphiteCore/NotePreviewDocument.swift#L540-L606), [LaTeXCompatibility.swift:93-101](../../Sources/GraphiteCore/LaTeXCompatibility.swift#L93-L101)) → `rewritingAlignments` calls itself on each body with no depth parameter ([LaTeXCompatibility.swift:259-277](../../Sources/GraphiteCore/LaTeXCompatibility.swift#L259-L277), recursion at [LaTeXCompatibility.swift:271](../../Sources/GraphiteCore/LaTeXCompatibility.swift#L271)) → `environmentEnd` rescans the remaining text at every level ([LaTeXCompatibility.swift:281-301](../../Sources/GraphiteCore/LaTeXCompatibility.swift#L281-L301)) → time grows with the square of the formula's length, and the recursion depth equals the nesting depth.
- **Minimal fix:** Add a `depth` parameter to `rewritingAlignments` and stop rewriting below a named maximum (16, like callouts at [NotePreviewDocument.swift:40](../../Sources/GraphiteCore/NotePreviewDocument.swift#L40)).
- **Rule that prevents the class:** bounded parsing of untrusted input
- **Aliases:** none
- **Verifier notes:** What settles the crash: a test in the style of `CrashLoopRegressionTests` that calls `LaTeXCompatibility.normalized` on 5,000 nested `aligned` environments on a 512 KB thread. The slowdown alone is certain: each level copies the body (`substring`) and runs a regex search and an `environmentEnd` scan over the rest. I rate it Medium rather than Low because a crash would repeat whenever the note is shown, as in BUG-MDCORE-01.

#### BUG-MDCORE-06 A private-use character in a note (U+E000–E006, E00A–E00B) shows as "�" in Live Preview's rendered tables and callouts, and as itself in reading view
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "notes with icon-font characters")
- **Reach:** iPad, iPhone, Mac; only notes with icon-font private-use glyphs inside blocks Live Preview draws as views.
- **Trigger:** A table cell or callout title holding, for example, U+E001, viewed in Live Preview.
- **Path:** Live Preview text goes through `LivePreviewText.prepared` ([LivePreviewWidgets.swift:272](../../Sources/GraphiteUI/LivePreviewWidgets.swift#L272), [LivePreviewWidgets.swift:376](../../Sources/GraphiteUI/LivePreviewWidgets.swift#L376)) → `ObsidianInlineMarkup.preparedForReading` with no escaping ([LivePreviewWidgets.swift:430-449](../../Sources/GraphiteUI/LivePreviewWidgets.swift#L430-L449)) → `replacingMarkerCharacters` writes U+FFFD for those scalars ([NotePreviewDocument.swift:350](../../Sources/GraphiteCore/NotePreviewDocument.swift#L350), [NotePreviewDocument.swift:367](../../Sources/GraphiteCore/NotePreviewDocument.swift#L367), [NotePreviewDocument.swift:386-394](../../Sources/GraphiteCore/NotePreviewDocument.swift#L386-L394)). Reading view escapes first ([MarkdownPreview.swift:571-573](../../Sources/GraphiteUI/MarkdownPreview.swift#L571-L573), [MarkdownPreview.swift:210-222](../../Sources/GraphiteUI/MarkdownPreview.swift#L210-L222)), so Core sees no marker, and the parser restores the original ([MarkdownPreview.swift:1970-1991](../../Sources/GraphiteUI/MarkdownPreview.swift#L1970-L1991)).
- **Minimal fix:** Wrap the input of `LivePreviewText.prepared` in `ReadingMarkerEscaping.escaping`, as `readingText` does; `ObsidianMarkdownText` already restores the stand-ins.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** I read the restore call site the report left open (`restoreEscapedCharacters`, lines 1970-1991); it handles only escape-lead pairs, so the U+FFFD written on the Live Preview path stays. Cosmetic.

### VAULT

#### BUG-VAULT-01 Renaming a file to a name another file shares except for a non-ASCII capital rewrites links to a bare name that then resolves to two files
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Normal rename path with link updates")
- **Reach:** iPad, iPhone, Mac; normal rename-with-"Update links" path; rare trigger (two names differing only in the case of a non-ASCII letter: `Éclair`/`éclair`, `Über`/`über`, `Δ`/`δ`).
- **Trigger:** `Other/éclair.md` exists and `Linker.md` contains `[[Old]]`; rename `Notes/Old.md` to `Notes/Éclair.md` and accept "Update links".
- **Path:** the planner records the rename as a name change ([VaultFileOperations.swift:97](../../Sources/GraphiteIndex/VaultFileOperations.swift#L97)) and asks whether the new name is unique ([VaultFileOperations.swift:181](../../Sources/GraphiteIndex/VaultFileOperations.swift#L181)) → `nameCount` calls `fileCount(named:excluding:)` ([VaultFileOperations.swift:356-364](../../Sources/GraphiteIndex/VaultFileOperations.swift#L356-L364)) → that query compares `name_key = ? COLLATE NOCASE` ([VaultFileOperations.swift:389-394](../../Sources/GraphiteIndex/VaultFileOperations.swift#L389-L394)); NOCASE folds ASCII only, as the index's own migration note says ([VaultIndex.swift:154-159](../../Sources/GraphiteIndex/VaultIndex.swift#L154-L159)), so `éclair.md` is not counted → the renamed file adds 1 ([VaultFileOperations.swift:361](../../Sources/GraphiteIndex/VaultFileOperations.swift#L361)) → count 1, `isNameUnique` true → `[[Old]]` is a bare name ([LinkRewriter.swift:509](../../Sources/GraphiteCore/LinkRewriter.swift#L509)), `unchangedName` returns nil because the name changed ([LinkRewriter.swift:487-493](../../Sources/GraphiteCore/LinkRewriter.swift#L487-L493)), and `pathPart` returns `Éclair` ([LinkRewriter.swift:471-473](../../Sources/GraphiteCore/LinkRewriter.swift#L471-L473)) → the move writes `[[Éclair]]` ([VaultFileOperations.swift:244](../../Sources/GraphiteIndex/VaultFileOperations.swift#L244)) → resolving it: no direct candidate at the root ([VaultIndex.swift:366-376](../../Sources/GraphiteIndex/VaultIndex.swift#L366-L376)), the name lookup by `folded_name` returns both files ([VaultIndex.swift:393](../../Sources/GraphiteIndex/VaultIndex.swift#L393), [VaultIndex.swift:399](../../Sources/GraphiteIndex/VaultIndex.swift#L399)) → backlinks accept only a single resolution ([VaultIndex.swift:491-492](../../Sources/GraphiteIndex/VaultIndex.swift#L491-L492)).
- **Minimal fix:** In `fileCount(named:excluding:)`, compare `folded_name = ?` with `VaultIndex.foldedKey(fileName)`, as the public `fileCount(named:)` already does ([VaultIndex.swift:419-422](../../Sources/GraphiteIndex/VaultIndex.swift#L419-L422)).
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** The function's doc comment claims names "compare as `fileCount(named:)` and the Wikilink resolver compare them" ([VaultFileOperations.swift:387-388](../../Sources/GraphiteIndex/VaultFileOperations.swift#L387-L388)); the SQL contradicts it. The other uniqueness check, in `linkMention`, uses the folded count ([WorkspaceMentions.swift:64](../../Sources/GraphiteUI/WorkspaceMentions.swift#L64)), so only the rename planner is affected. The existing test uses ASCII names only ([FileOperationTests.swift:69-74](../../Tests/GraphiteIndexTests/FileOperationTests.swift#L69-L74)).

#### BUG-VAULT-02 A `bookmarks.json` that Graphite cannot read shows as "no bookmarks", with no error
- **Verdict:** Confirmed (size trigger traced; the file-provider trigger depends on provider behaviour)
- **Severity:** Medium  (reported: none given)
- **Reach:** iPad, iPhone, Mac; fallback path: a file over 1 MiB (rare), or a coordinated read the provider fails (cloud vault offline). The same read serves `community-plugins.json`, `templates.json` and `daily-notes.json`.
- **Trigger:** `.obsidian/bookmarks.json` is larger than 1 MiB, or its coordinated read fails.
- **Path:** `reloadBookmarks` calls `store.bookmarks()` inside a `do/catch` ([WorkspaceBookmarks.swift:7-11](../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L7-L11)) → `bookmarks()` reads through `configurationData` ([VaultStore.swift:178-180](../../Sources/GraphiteCore/VaultStore.swift#L178-L180)) → `try? writer.read(url, maximumBytes: 1_048_576)` ([VaultStore.swift:254-257](../../Sources/GraphiteCore/VaultStore.swift#L254-L257), limit at [VaultStore.swift:70](../../Sources/GraphiteCore/VaultStore.swift#L70)) swallows the `oversized` throw and coordination errors ([AtomicFileWriter.swift:48-57](../../Sources/GraphiteCore/AtomicFileWriter.swift#L48-L57)) → `BookmarkList(configurationData: nil)` is an empty list ([Bookmarks.swift:170-171](../../Sources/GraphiteCore/Bookmarks.swift#L170-L171)) → no throw, so the `catch` never sets `errorMessage` → the sidebar shows no bookmarks; bookmark-following on rename is skipped because its guard reads the empty list ([WorkspaceBookmarks.swift:93-95](../../Sources/GraphiteUI/WorkspaceBookmarks.swift#L93-L95)).
- **Minimal fix:** Make `configurationData(at:)` throw (return nil only when the file does not exist) and let `bookmarks()`, `communityPluginList()` and the settings readers propagate the error to the presenter.
- **Rule that prevents the class:** failed reads are never empty results
- **Aliases:** none
- **Verifier notes:** No data is lost: writes re-read with `try` in `saveConfiguration` ([VaultStore.swift:265](../../Sources/GraphiteCore/VaultStore.swift#L265)) and fail; `updateBookmarks` and `updateCommunityPluginList` first test `configurationData == nil` ([VaultStore.swift:188-192](../../Sources/GraphiteCore/VaultStore.swift#L188-L192), [CommunityPluginList.swift:63-67](../../Sources/GraphiteCore/CommunityPluginList.swift#L63-L67)) but then go through the throwing path, so the file is never overwritten with an empty list. The failed add then shows the misleading "current editor's memory budget" message ([AtomicFileWriter.swift:50](../../Sources/GraphiteCore/AtomicFileWriter.swift#L50)). For the provider case: on systems where an evicted iCloud file is not visible under its own name, `fileExists` is false and the outcome is the same "none"; what settles it is a read of a dataless file offline on the current iPadOS.

#### BUG-VAULT-03 A `content:` or plain regular-expression search that matches empty text lists every canvas
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "Normal search path, with an unusual query")
- **Reach:** iPad, iPhone, Mac; normal search path with an unusual query (`/^$/`, `/^\s*$/`, `content:/x*/`); vaults with canvases.
- **Trigger:** Search `content:/^$/` (or `/^$/` without an operator) in a vault with `.canvas` files.
- **Path:** a canvas is parsed into non-optional semantics ([VaultIndex.swift:278-280](../../Sources/GraphiteIndex/VaultIndex.swift#L278-L280), [CanvasLinks.swift:74](../../Sources/GraphiteCore/CanvasLinks.swift#L74), [CanvasLinks.swift:86](../../Sources/GraphiteCore/CanvasLinks.swift#L86)) → `write` stores it with content state `.indexed` ([VaultIndex.swift:324-325](../../Sources/GraphiteIndex/VaultIndex.swift#L324-L325)) and an empty search body ([VaultIndex.swift:261-263](../../Sources/GraphiteIndex/VaultIndex.swift#L261-L263), [VaultIndex.swift:332](../../Sources/GraphiteIndex/VaultIndex.swift#L332)) → the regex content condition is `files.contentIndexed = 1 AND … graphite_regexp(?, body)`, marked exact ([VaultSearch.swift:344-352](../../Sources/GraphiteIndex/VaultSearch.swift#L344-L352)) → exact conditions skip the matcher ([VaultSearch.swift:177](../../Sources/GraphiteIndex/VaultSearch.swift#L177)) and every row is accepted ([VaultSearch.swift:189-190](../../Sources/GraphiteIndex/VaultSearch.swift#L189-L190)) → the empty body matches `^$`, so each canvas is listed. In a non-exact expression the matcher gives a canvas no content ([VaultSearch.swift:272](../../Sources/GraphiteIndex/VaultSearch.swift#L272), [SearchQuery.swift:912](../../Sources/GraphiteCore/SearchQuery.swift#L912)) and excludes it, so the two paths disagree.
- **Minimal fix:** Add `AND files.path NOT LIKE '%.canvas'` (or a `hasSearchableText` column) to the regex content condition, or store canvases with a content state other than `indexed`.
- **Rule that prevents the class:** contract test suites shared by every implementation
- **Aliases:** none
- **Verifier notes:** The test that pins "patterns matching empty text skip attachments and unread notes" has no canvas in its fixture ([IndexSearchFixTests.swift:206-221](../../Tests/GraphiteIndexTests/IndexSearchFixTests.swift#L206-L221)). I add that the plain `/^$/` query (target `.note`) uses the same `contentCondition` ([VaultSearch.swift:349](../../Sources/GraphiteIndex/VaultSearch.swift#L349)) and lists canvases too.

### BASES

#### BUG-BASES-01 Turning off "Default Zoom" on a map written with `zoom:` saves nothing and still reports success
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal editing path, but only for map views written with the non-standard `zoom:` key (hand-written or published bases). Rare.
- **Trigger:** a map view holds `zoom: 12` and no `defaultZoom`. The person opens Edit View, turns "Default Zoom" off and saves.
- **Path:** the reader accepts both names, `defaultZoom` first and then `zoom` ([BaseDefinition.swift:495](../../Sources/GraphiteCore/BaseDefinition.swift#L495)) → the draft starts at 12 ([BaseViewEditorSheet.swift:44](../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L44)) → the toggle sets `draft.defaultZoom = nil` ([BaseViewEditorSheet.swift:465](../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L465)) → `apply` calls `setOption("defaultZoom", number: nil)` ([BaseViewEditorSheet.swift:67](../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L67)) → the editor assigns nil to the `defaultZoom` key only, which is absent ([BaseDefinitionEditor.swift:297-299](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L297-L299)), and stores the same view list back ([BaseDefinitionEditor.swift:341-347](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L341-L347)) → `yaml()` finds the edited tree means the same as the original and returns the original text ([BaseDefinitionEditor.swift:66](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L66)) → `editDefinition` saves those identical bytes and reloads ([BaseDocumentModel.swift:339-350](../../Sources/GraphiteUI/BaseDocumentModel.swift#L339-L350)) → `saveEdit` returns no message, so the sheet dismisses as a success ([BaseViewEditorSheet.swift:318-323](../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L318-L323)) → the reload reads `zoom: 12` again.
- **Minimal fix:** when an option is cleared, remove every name the reader accepts for it (`defaultZoom` and `zoom`, `mapHeight` and `height`). Keep these aliases in one table that both the reader and the editor use.
- **Rule that prevents the class:** *New rule:* reader and writer share one schema: every key name, alias or merge the reader honours is one the writer edits.
- **Aliases:** none
- **Verifier notes:** no test edits a map option. The only `zoom:` tests parse ([BaseQueryTests.swift:146](../../Tests/GraphiteCoreTests/BaseQueryTests.swift#L146), [CoreBasesDefinitionQueryFixTests.swift:216](../../Tests/GraphiteCoreTests/CoreBasesDefinitionQueryFixTests.swift#L216)). Changing the zoom to another value works, because the new `defaultZoom` key wins over `zoom` on the next read. Only turning the option off fails. `mapHeight`/`height` ([BaseDefinition.swift:496](../../Sources/GraphiteCore/BaseDefinition.swift#L496)) share the same latent shape, but the editor never sets a height today.

#### BUG-BASES-02 A base resolves a Markdown link through another note's alias, although backlinks do not
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal query path. It needs an extension-less Markdown link whose text equals an alias and names no file, which is rare.
- **Trigger:** `Notes/A.md` contains `[see](Bob)`, `People/Robert.md` has `aliases: [Bob]`, and no file is named `Bob`. A base filters `file.hasLink(file("People/Robert.md"))`.
- **Path:** the index stores the Markdown target `Bob` with `isWiki` false ([VaultIndex.swift:344](../../Sources/GraphiteIndex/VaultIndex.swift#L344), [VaultIndex.swift:510-518](../../Sources/GraphiteIndex/VaultIndex.swift#L510-L518)) → the prefilter keeps `A.md`, because Robert's aliases are among the accepted targets ([BaseRecordQueries.swift:149-153](../../Sources/GraphiteIndex/BaseRecordQueries.swift#L149-L153)) → the record keeps `isWiki` ([BaseRecordQueries.swift:221-222](../../Sources/GraphiteIndex/BaseRecordQueries.swift#L221-L222)), but `hasLink` collects bare target strings ([BaseEvaluator.swift:438-442](../../Sources/GraphiteCore/BaseEvaluator.swift#L438-L442), [BaseEvaluator.swift:1168-1172](../../Sources/GraphiteCore/BaseEvaluator.swift#L1168-L1172)) → `link(_:from:pointsTo:)` calls `resolveLink` ([BaseEvaluator.swift:460-461](../../Sources/GraphiteCore/BaseEvaluator.swift#L460-L461), [BaseEvaluator.swift:157](../../Sources/GraphiteCore/BaseEvaluator.swift#L157)) → the provider always passes `isWiki: true` ([BaseRecordQueries.swift:253-254](../../Sources/GraphiteIndex/BaseRecordQueries.swift#L253-L254)) → the Wikilink branch matches the alias ([VaultIndex.swift:392-394](../../Sources/GraphiteIndex/VaultIndex.swift#L392-L394)) → `hasLink` is true. Backlinks resolve the same row with its stored kind ([VaultIndex.swift:481-491](../../Sources/GraphiteIndex/VaultIndex.swift#L481-L491)), and the Markdown branch looks up file names only ([VaultIndex.swift:395-397](../../Sources/GraphiteIndex/VaultIndex.swift#L395-L397)). So `A.md` is not among Robert's backlinks.
- **Minimal fix:** keep the link kind in the evaluator's link targets and pass it to `resolveLinkTarget(_:from:isWiki:)`. Property links stay Wikilink-resolved, as the backlink query already does ([VaultIndex.swift:465-467](../../Sources/GraphiteIndex/VaultIndex.swift#L465-L467)).
- **Rule that prevents the class:** one owner per business rule (link resolution, including the kind of link)
- **Aliases:** none
- **Verifier notes:** the same mismatch reaches `file.links` → `asFile()`, because `BaseLink` carries no kind ([BaseEvaluator.swift:429](../../Sources/GraphiteCore/BaseEvaluator.swift#L429), [BaseEvaluator.swift:1185-1186](../../Sources/GraphiteCore/BaseEvaluator.swift#L1185-L1186)). A Markdown link with an extension (`Bob.md`) does not match an alias. I rate it lower than the report implies because the link must already be broken by Obsidian's rules.

#### BUG-BASES-03 `file.hasLink(file("Name"))` leaves out matching notes when a note of that name sits at the vault root
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal query path for filters that call `file("…")` with a bare name, in vaults where that name exists in several folders. Duplicate names are common (`README`, `Index`).
- **Trigger:** `Note.md` at the root and `A/Note.md`. `A/X.md` contains `[[A/Note]]`. A base filters `file.hasLink(file("Note"))`.
- **Path (evaluator):** `file("Note")` is evaluated with the row's path as source ([BaseEvaluator.swift:796-799](../../Sources/GraphiteCore/BaseEvaluator.swift#L796-L799)) → plain text is not a link ([BaseValue.swift:165-195](../../Sources/GraphiteCore/BaseValue.swift#L165-L195)), so `filePath` resolves it from the row ([BaseEvaluator.swift:480-485](../../Sources/GraphiteCore/BaseEvaluator.swift#L480-L485)) → the file beside the note comes first ([MarkdownSemantics.swift:898-900](../../Sources/GraphiteCore/MarkdownSemantics.swift#L898-L900)), giving `A/Note.md` → `[[A/Note]]` from `A/X.md` resolves to `A/Note.md` → the row matches.
- **Path (prefilter):** a function call with literal arguments does not depend on the row ([BaseExpression.swift:493](../../Sources/GraphiteCore/BaseExpression.swift#L493)) → `constantValue` evaluates it with no record ([BaseRecordPrefilter.swift:99-101](../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L99-L101)) → `resolveLink` with no source resolves from the root ([BaseEvaluator.swift:156-161](../../Sources/GraphiteCore/BaseEvaluator.swift#L156-L161)) and gives `Note.md` → requirement `.linksTo(.path(Note.md))` ([BaseRecordPrefilter.swift:120](../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L120)) → the accepted targets are the trailing forms of `Note.md` and its aliases, relative endings and padded forms ([BaseRecordQueries.swift:143-172](../../Sources/GraphiteIndex/BaseRecordQueries.swift#L143-L172), [BaseRecordQueries.swift:179-187](../../Sources/GraphiteIndex/BaseRecordQueries.swift#L179-L187)) → the stored target `A/Note` ([VaultIndex.swift:511](../../Sources/GraphiteIndex/VaultIndex.swift#L511)) matches none of them → `A/X.md` is never loaded ([BaseDocumentModel.swift:203-204](../../Sources/GraphiteUI/BaseDocumentModel.swift#L203-L204)).
- **Minimal fix:** in the prefilter, treat `file(text)` as `.linksTo(.target(text))`, which widens to every file of that name ([BaseRecordQueries.swift:124-141](../../Sources/GraphiteIndex/BaseRecordQueries.swift#L124-L141)). Alternatively, count calls to `file()`/`link()` with a relative text as row-dependent.
- **Rule that prevents the class:** one owner per business rule (where a written name resolves from)
- **Aliases:** none
- **Verifier notes:** this breaks the superset contract the prefilter states ([BaseRecordPrefilter.swift:38-40](../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L38-L40)). No problem is shown, so the person sees a silently short list. `file("A/Note.md")` (a full path) is not affected, because it names one file from every folder.

#### BUG-BASES-04 Tapping a link cell opens the root file while the base resolves the link beside its note
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal tap path, but only for links written as a folder path that exists both relative to the note and from the root. Rare.
- **Trigger:** `Folder/A.md` has `related: "[[Sub/Note.md]]"`. Both `Sub/Note.md` and `Folder/Sub/Note.md` exist. The person taps the link in a table cell.
- **Path:** the cell's link carries source `Folder/A.md` ([BaseFileRecord.swift:119-120](../../Sources/GraphiteCore/BaseFileRecord.swift#L119-L120)) → the button calls `openLink` ([BaseValueViews.swift:113](../../Sources/GraphiteUI/BaseValueViews.swift#L113)) → `model.resolve` ([BaseDocumentView.swift:454-457](../../Sources/GraphiteUI/BaseDocumentView.swift#L454-L457)) tests the written path as a vault-root file first and returns `Sub/Note.md` ([BaseDocumentModel.swift:435-436](../../Sources/GraphiteUI/BaseDocumentModel.swift#L435-L436)). The index resolves the same link beside the note first ([VaultIndex.swift:366-375](../../Sources/GraphiteIndex/VaultIndex.swift#L366-L375), [MarkdownSemantics.swift:898-900](../../Sources/GraphiteCore/MarkdownSemantics.swift#L898-L900)), and `asFile()` uses that order ([BaseEvaluator.swift:1185-1186](../../Sources/GraphiteCore/BaseEvaluator.swift#L1185-L1186)), giving `Folder/Sub/Note.md`.
- **Minimal fix:** drop the root-first check in `resolve` and call `index.resolve(link.target, from: source)` only. If the folder-versus-note case the check was added for still needs it, filter folders inside the index lookup.
- **Rule that prevents the class:** one owner per business rule (link resolution)
- **Aliases:** none
- **Verifier notes:** the only test calls `resolve` without a source and without a duplicate relative path ([UiBasesDocumentModelTests.swift:201-212](../../Tests/GraphiteUITests/UiBasesDocumentModelTests.swift#L201-L212)), so it does not pin the opposite behaviour.

#### BUG-BASES-05 Editing the first view of a base whose `views` come from a root merge key replaces all views with one table
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Only bases with a root-level `<<:` that supplies `views`, which are hand-written and rare.
- **Trigger:** the root mapping takes `views` through `<<: *defaults`. The person edits the first view (header sort saved to the view, column width, Edit View).
- **Path:** the reader applies merge keys ([BaseDefinition.swift:289](../../Sources/GraphiteCore/BaseDefinition.swift#L289), [BaseDefinition.swift:307-329](../../Sources/GraphiteCore/BaseDefinition.swift#L307-L329)) and shows the merged views → `editDefinition`'s target check passes against those merged views ([BaseDocumentModel.swift:334](../../Sources/GraphiteUI/BaseDocumentModel.swift#L334)) → the editor reads the raw root mapping ([BaseDefinitionEditor.swift:322](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L322)), finds no `views` and substitutes one default table ([BaseDefinitionEditor.swift:333-336](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L333-L336)) → `updateView(at: 0)` writes an explicit `views:` with that table ([BaseDefinitionEditor.swift:341-347](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L341-L347)) → the read-back compares against the edited raw tree and passes ([BaseDefinitionEditor.swift:79](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L79)) → on the next read the explicit key wins over the merged one ([BaseDefinition.swift:318-324](../../Sources/GraphiteCore/BaseDefinition.swift#L318-L324)).
- **Minimal fix:** `ensuredViews` refuses (throws `unreadableViews`) when the root has a merge key and no explicit `views`, as it already refuses other shapes it cannot edit.
- **Rule that prevents the class:** *New rule:* reader and writer share one schema: every key name, alias or merge the reader honours is one the writer edits.
- **Aliases:** none
- **Verifier notes:** the report could not settle whether Yams keeps `<<` unresolved. An editor test settles it: after an edit, the editor writes `{<<: *shared, name: Last}` back verbatim ([CoreBasesEdgeCaseFixTests.swift:175-190](../../Tests/GraphiteCoreTests/CoreBasesEdgeCaseFixTests.swift#L175-L190)), so the parsed tree holds `<<` as a plain key. Editing a later view is refused instead ([BaseDefinitionEditor.swift:343](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L343)). The merged views stay in the file under their anchor, so source editing can recover them.

### CANVAS

#### BUG-CANVAS-01 Undo while typing in a text card discards the typed text and undoes the step before it
- **Verdict:** Confirmed
- **Severity:** High (reported: none given; "Traced")
- **Reach:** iPad and iPhone (canvas editing is UIKit-only, [WorkspaceCanvas.swift:14-17](../../Sources/GraphiteUI/WorkspaceCanvas.swift#L14-L17)). Normal editing path. It happens every time Undo is tapped before typing has paused for 0.9 s. Each keystroke restarts the autosave timer, so the text lost is everything typed since the last pause, not just the last 0.9 s.
- **Trigger:** In Write, the person edits an existing text card. Some earlier step is in the canvas history (a move, a colour change, an earlier "Edit Text"). The person taps Undo in the toolbar, the control row or the tab bar before typing has paused for 0.9 s.
- **Path:**
  1. Every keystroke runs `updateTextEdit`, through the `TextEditor` binding ([CanvasCardViews.swift:213](../../Sources/GraphiteUI/CanvasCardViews.swift#L213)). The text is stored only in `textEdit`, and autosave is rescheduled ([CanvasSession.swift:279-283](../../Sources/GraphiteUI/CanvasSession.swift#L279-L283), [299-306](../../Sources/GraphiteUI/CanvasSession.swift#L299-L306)).
  2. Undo is shown while writing ([CanvasPane.swift:46](../../Sources/GraphiteUI/CanvasPane.swift#L46), [147](../../Sources/GraphiteUI/CanvasPane.swift#L147); [DocumentModeToggle.swift:178-180](../../Sources/GraphiteUI/DocumentModeToggle.swift#L178-L180)). It calls `availability.undo()` ([UndoRedoButtons.swift:20-22](../../Sources/GraphiteUI/UndoRedoButtons.swift#L20-L22)), which calls `followedUndoManager.undo()` ([UndoAvailability.swift:52-55](../../Sources/GraphiteUI/UndoAvailability.swift#L52-L55)). That is the session's own manager ([CanvasSession.swift:163](../../Sources/GraphiteUI/CanvasSession.swift#L163)). Nothing on this path calls `commitTextEdit`.
  3. The registered handler runs `applyFromHistory`. It sets `textEdit = nil` and then applies the inverse patch of the earlier step ([CanvasSession.swift:238-244](../../Sources/GraphiteUI/CanvasSession.swift#L238-L244)).
  4. The pending autosave runs `save()` → `commitTextEdit()`. Its guard finds `textEdit == nil` and returns ([CanvasSession.swift:286-288](../../Sources/GraphiteUI/CanvasSession.swift#L286-L288), [312](../../Sources/GraphiteUI/CanvasSession.swift#L312)). The editor view is replaced by the rendered card, because `isEdited` is now false ([CanvasCardViews.swift:86-90](../../Sources/GraphiteUI/CanvasCardViews.swift#L86-L90)).
  5. Outcome: the typed text exists nowhere. Redo re-applies only the earlier step.
- **Minimal fix:** In `applyFromHistory`, and in the Undo and Redo entry points, call `commitTextEdit()` before undoing. The pending text then becomes its own "Edit Text" step, and Undo removes that step first.
- **Rule that prevents the class:** *New rule:* buffered (uncommitted) edits are committed or explicitly discarded at one choke point before any history, save, move or unload step.
- **Aliases:** none
- **Verifier notes:** No test covers Undo during editing. The only test that uses `updateTextEdit` saves directly ([CanvasTests.swift:217-219](../../App/Tests/CanvasTests.swift#L217-L219)). A hardware ⌘Z goes to the `UITextView`'s own undo manager and does not hit this path; the toolbar and control-row buttons do. The report understates the loss: continuous typing never lets autosave commit, so a paragraph can be lost, not only the last 0.9 s.

#### BUG-CANVAS-02 Edits made to an open canvas while it or its folder moves are lost
- **Verdict:** Confirmed
- **Severity:** Medium (reported: none given; "Traced")
- **Reach:** iPad and iPhone (editing). Normal rename and move path. Only edits made while the move runs are affected: short for one file, seconds for a folder move with many link rewrites. The canvas can be in the other split, or the move can come from the sidebar while the person edits.
- **Trigger:** A canvas open in a tab is renamed or moved, or a folder holding it is. During the await on the move, the person moves a card or types in a card.
- **Path:**
  1. `completeMove` saves open documents, then awaits `fileOperations.move` ([WorkspaceFileManagement.swift:141-143](../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L141-L143)).
  2. Edits made during the await are collected only from `markdownSession`s ([WorkspaceFileManagement.swift:194-199](../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L194-L199)).
  3. `followMoveInNavigation` unloads every tab inside the moved path ([WorkspaceModel.swift:1201-1202](../../Sources/GraphiteUI/WorkspaceModel.swift#L1201-L1202)). `unload()` sets `canvasSession = nil` ([WorkspaceTabs.swift:40-42](../../Sources/GraphiteUI/WorkspaceTabs.swift#L40-L42)).
  4. The session's autosave holds it weakly, so after the release `self?.save()` does nothing ([CanvasSession.swift:301-305](../../Sources/GraphiteUI/CanvasSession.swift#L301-L305)). If the autosave fires during the move, `save()` writes to the old path with `.revision`. The writer throws `.conflict` because the file is gone ([AtomicFileWriter.swift:81-82](../../Sources/GraphiteCore/AtomicFileWriter.swift#L81-L82)). The banner that shows this belongs to a session that is released at step 3.
  5. Outcome: the tab reloads the canvas from its new path without those edits, and nothing reports it.
- **Minimal fix:** Collect canvas sessions with `hasUnsavedChanges` inside the moved path in `unsavedEdits(inside:movedTo:)`, as is done for notes. Write their `file.data` to the new path, or to a " Graphite edits" copy when the revision differs, before `followMoveInNavigation`.
- **Rule that prevents the class:** contract test suites shared by every implementation (the "edits during move are kept" contract is implemented and tested only for the note session)
- **Aliases:** none
- **Verifier notes:** The pre-move save does include canvases ([WorkspaceFileManagement.swift:105-107](../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L105-L107)), so only edits made during the await are lost. I rate this Medium rather than High: the loss is silent, but it needs editing at the same moment as a move.

#### BUG-CANVAS-03 On the Mac, the content of a text, note or base card longer than its card cannot be scrolled
- **Verdict:** Confirmed
- **Severity:** Medium (reported: none given; "Traced")
- **Reach:** Mac only. Normal reading path, every canvas with an overflowing card.
- **Trigger:** On the Mac, the person opens a canvas whose text, note or base card holds more than fits, and scrolls over it.
- **Path:**
  1. The Mac `CanvasBoardHost` registers a drag, a magnify and a double tap, and no single tap ([CanvasBoardHost.swift:206-231](../../Sources/GraphiteUI/CanvasBoardHost.swift#L206-L231)). Only the UIKit host calls `session.tap` ([CanvasBoardHost.swift:147-150](../../Sources/GraphiteUI/CanvasBoardHost.swift#L147-L150)).
  2. `focusedNodeIdentifier` is assigned only in `tap` ([CanvasInteraction.swift:220-222](../../Sources/GraphiteUI/CanvasInteraction.swift#L220-L222)). The other writes are resets ([CanvasSession.swift:90](../../Sources/GraphiteUI/CanvasSession.swift#L90), [256](../../Sources/GraphiteUI/CanvasSession.swift#L256)), so on the Mac `isFocused` is always false ([CanvasBoardView.swift:345-351](../../Sources/GraphiteUI/CanvasBoardView.swift#L345-L351)).
  3. Text cards: `.scrollDisabled(!isFocused || isWriting)` ([CanvasCardViews.swift:106-109](../../Sources/GraphiteUI/CanvasCardViews.swift#L106-L109)). File cards pass `isScrollable: isFocused && !isWriting` ([CanvasCardViews.swift:92](../../Sources/GraphiteUI/CanvasCardViews.swift#L92)) to note content ([CanvasCardViews.swift:313](../../Sources/GraphiteUI/CanvasCardViews.swift#L313)) and to base content ([CanvasCardViews.swift:280](../../Sources/GraphiteUI/CanvasCardViews.swift#L280)).
  4. Outcome: only the top of each long card is visible. Zooming scales the card, so it reveals nothing more.
- **Minimal fix:** On macOS, add `.onTapGesture { location in session.tap(atViewPoint: location) }` beside the double tap. Alternatively, enable card scrolling on the Mac, which has no Write mode and so no conflict with moving cards.
- **Rule that prevents the class:** contract test suites shared by every implementation (the two `CanvasBoardHost` implementations do not share an interaction contract)
- **Aliases:** none
- **Verifier notes:** `isWriting` stays false on the Mac, because it is set only under `canImport(UIKit)` ([WorkspaceCanvas.swift:14-17](../../Sources/GraphiteUI/WorkspaceCanvas.swift#L14-L17), [33-35](../../Sources/GraphiteUI/WorkspaceCanvas.swift#L33-L35)). Note cards can be opened from their title. A text card's overflow has no other view on the Mac, which is why I rate this Medium.

#### BUG-CANVAS-04 A card resized or grouped beyond 1,000,000 pixels disappears from the board after the edit
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Traced")
- **Reach:** iPad and iPhone (editing). Edge case: a group around cards more than 1,000,000 px apart, or about ten successive maximal resizes at the 0.01 minimum zoom ([CanvasGeometry.swift:8](../../Sources/GraphiteCore/CanvasGeometry.swift#L8)). Undo restores the card.
- **Trigger:** The person groups cards whose union is wider or taller than 1,000,000 px, or resizes a card beyond that.
- **Path:**
  1. Resizing has no upper bound ([CanvasGeometry.swift:356-384](../../Sources/GraphiteCore/CanvasGeometry.swift#L356-L384)). A new group is the union of the selection plus padding ([CanvasInteraction.swift:447-451](../../Sources/GraphiteUI/CanvasInteraction.swift#L447-L451)).
  2. The edit writes numbers clamped only to ±10,000,000 ([CanvasJSON.swift:366-369](../../Sources/GraphiteCore/CanvasJSON.swift#L366-L369); [CanvasFileEditing.swift:136-139](../../Sources/GraphiteCore/CanvasFileEditing.swift#L136-L139), [254-255](../../Sources/GraphiteCore/CanvasFileEditing.swift#L254-L255)).
  3. `applying` re-reads the bytes ([CanvasFileEditing.swift:102](../../Sources/GraphiteCore/CanvasFileEditing.swift#L102)). `frame(of:)` rejects sides over `maximumSideLength` ([CanvasFile.swift:155](../../Sources/GraphiteCore/CanvasFile.swift#L155), [289](../../Sources/GraphiteCore/CanvasFile.swift#L289)). The card is skipped, not thrown ([CanvasFile.swift:201](../../Sources/GraphiteCore/CanvasFile.swift#L201)), and counted as unreadable ([CanvasFile.swift:232](../../Sources/GraphiteCore/CanvasFile.swift#L232)).
  4. `adopt` drops it from the selection ([CanvasSession.swift:254](../../Sources/GraphiteUI/CanvasSession.swift#L254)). The banner says the card cannot be shown ([CanvasPane.swift:126-127](../../Sources/GraphiteUI/CanvasPane.swift#L126-L127)). For a group, `nameRequest` targets a card the session no longer lists ([CanvasInteraction.swift:460](../../Sources/GraphiteUI/CanvasInteraction.swift#L460)).
- **Minimal fix:** Clamp width and height to `CanvasFile.maximumSideLength` in `setFrames` and `add`, the same bound the reader enforces. Or refuse the edit with a message.
- **Rule that prevents the class:** persisted types have one validating construction path, golden tests, explicit encoding and a version
- **Aliases:** none
- **Verifier notes:** No caller clamps before `perform`: `endDrag` passes `previewFrames` unchanged ([CanvasInteraction.swift:185-187](../../Sources/GraphiteUI/CanvasInteraction.swift#L185-L187)). The file stays valid for Obsidian, and the data is kept.

#### BUG-CANVAS-05 Renaming a note named by a canvas Graphite cannot read leaves the canvas pointing at the old path without a report
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Partly traced")
- **Reach:** All platforms. Only canvases that Graphite refuses (more than 50,000 cards, more than 100,000 connections, nesting deeper than 64, too many values) but Obsidian opens. Rare.
- **Trigger:** Such a canvas has a file card naming `A.md`. The person renames `A.md` in Graphite.
- **Path:**
  1. The index parses canvases with `CanvasLinks.semantics` ([VaultIndex.swift:278-280](../../Sources/GraphiteIndex/VaultIndex.swift#L278-L280)). It returns no links when `CanvasFile` throws, because of `if let file = try? …` ([CanvasLinks.swift:74-87](../../Sources/GraphiteCore/CanvasLinks.swift#L74-L87)). The canvas therefore has no link rows.
  2. `linkUpdates(forMoving:)` takes its sources from `index.linkingNotes(to:)` ([VaultFileOperations.swift:88-94](../../Sources/GraphiteIndex/VaultFileOperations.swift#L88-L94)), which reads the backlink rows ([VaultFileOperations.swift:383-385](../../Sources/GraphiteIndex/VaultFileOperations.swift#L383-L385)). The canvas is not a source, so it never reaches the `notesNotUpdated` bookkeeping ([VaultFileOperations.swift:102-129](../../Sources/GraphiteIndex/VaultFileOperations.swift#L102-L129)).
  3. Outcome: the move report lists nothing, and the canvas's card names a path that no longer exists.
- **Minimal fix:** Have `CanvasLinks.semantics` report "unreadable" rather than "no links", and store a flag in the index. The move plan then lists every unreadable canvas that mentions the old path as text (a cheap substring check) in `notesNotUpdated`.
- **Rule that prevents the class:** failed reads are never empty results
- **Aliases:** none
- **Verifier notes:** I closed the gap the report left open: `linkingNotes` reads the same backlink rows that `semantics.links` fills, so the trace is complete.

#### BUG-CANVAS-06 A graph or map from the previous vault can be shown after a vault switch
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Partly traced")
- **Reach:** All platforms. A race: the old vault's `linkGraph()` or `placedNotes()` query must still be running when `openVault` reaches its reset, and the new vault's first scan must not have finished. The stale result lasts until that scan ends.
- **Trigger:** A local graph or map panel, or the full graph or map, is loading in a large vault. The person switches vaults and opens the graph or map before the new vault's first scan completes.
- **Path:**
  1. `vaultGraph()` captures `index` and `indexVersion`, awaits `index.linkGraph()`, and stores `graphCache` without checking that `self.index` is still the same ([WorkspaceGraph.swift:7-14](../../Sources/GraphiteUI/WorkspaceGraph.swift#L7-L14)). `placedNotes()` does the same ([WorkspaceMap.swift:8-18](../../Sources/GraphiteUI/WorkspaceMap.swift#L8-L18)).
  2. `linkGraph()` is one synchronous GRDB read inside the `VaultIndex` actor ([VaultGraph.swift:10-11](../../Sources/GraphiteIndex/VaultGraph.swift#L10-L11)). Cancelling the panel's `.task` does not stop it, so it completes.
  3. The switch clears the caches ([WorkspaceModel.swift:314](../../Sources/GraphiteUI/WorkspaceModel.swift#L314)) but does not change `indexVersion`. That only increments when a scan or refresh ends ([WorkspaceModel.swift:531](../../Sources/GraphiteUI/WorkspaceModel.swift#L531), [585](../../Sources/GraphiteUI/WorkspaceModel.swift#L585)).
  4. The old query resumes after the reset and writes the old graph under the current version. The new vault's `vaultGraph()` returns it ([WorkspaceGraph.swift:10](../../Sources/GraphiteUI/WorkspaceGraph.swift#L10)). Tapping a node opens a path the new vault lacks.
- **Minimal fix:** After the await, store the result only if `self.index === index` (as `refreshIndex` does at [WorkspaceModel.swift:586](../../Sources/GraphiteUI/WorkspaceModel.swift#L586)). Also key the cache by the index's identity, not only the version.
- **Rule that prevents the class:** every task has an owner that cancels it, latest-answer-wins through one primitive
- **Aliases:** none
- **Verifier notes:** I settled the open point: `linkGraph` does not observe cancellation. A related fault: `refreshIndex` increments `indexVersion` even when its `index` is no longer current ([WorkspaceModel.swift:583-586](../../Sources/GraphiteUI/WorkspaceModel.swift#L583-L586)). That can make the cache miss, which is harmless, but it is another unguarded write from an old vault.

### INK

#### BUG-INK-01 A recovered drawing draft reopens with the original background, losing the paper colour the user chose
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Traced")
- **Reach:** iPad and iPhone (the draft and recovery code is inside `#if canImport(UIKit)`, [GraphiteRootView.swift:171](../../Sources/GraphiteUI/GraphiteRootView.swift#L171), [GraphiteRootView.swift:586](../../Sources/GraphiteUI/GraphiteRootView.swift#L586)). Recovery path: it runs only after the system ends the app while a changed drawing is open. Every such recovery loses the colour, if the user changed it.
- **Trigger:** In the drawing editor the user picks another background ("Yellow Background"), the app goes to the background, the system ends it, and the user opens the vault again.
- **Path:**
  1. The Background picker writes `canvasController.background` ([DrawingEditor.swift:291-293](../../Sources/GraphiteUI/DrawingEditor.swift#L291-L293)), whose `didSet` sets `hasChanges` ([DrawingEditor.swift:468-474](../../Sources/GraphiteUI/DrawingEditor.swift#L468-L474)).
  2. On `.background` the editor calls `preserveDraft(currentContent)` ([DrawingEditor.swift:201-203](../../Sources/GraphiteUI/DrawingEditor.swift#L201-L203)). `currentContent` carries `canvasController.background` ([DrawingEditor.swift:324-327](../../Sources/GraphiteUI/DrawingEditor.swift#L324-L327)).
  3. The closure in the root view builds the description from the `request` captured when the cover opened ([GraphiteRootView.swift:177](../../Sources/GraphiteUI/GraphiteRootView.swift#L177), [GraphiteRootView.swift:185](../../Sources/GraphiteUI/GraphiteRootView.swift#L185)). `DrawingEditorDraft.init` stores `background = request.background` ([DrawingEditorDraftStore.swift:35](../../Sources/GraphiteUI/DrawingEditorDraftStore.swift#L35)). The draft SVG's payload gets `content.background`, the chosen one ([DrawingFileService.swift:211](../../Sources/GraphiteApple/DrawingFileService.swift#L211)), and `DrawingPayload` encodes `background` ([DrawingPayload.swift:218](../../Sources/GraphiteCore/DrawingPayload.swift#L218), [DrawingPayload.swift:236](../../Sources/GraphiteCore/DrawingPayload.swift#L236)).
  4. On the next vault open, `reopenDrawingDraft` calls `editorRequest(inVaultAt:)` ([GraphiteRootView.swift:192-193](../../Sources/GraphiteUI/GraphiteRootView.swift#L192-L193), [GraphiteRootView.swift:576](../../Sources/GraphiteUI/GraphiteRootView.swift#L576)). That method passes `background: draft.background` but takes strokes, width, pictures and paper from `payload` ([DrawingEditorDraftStore.swift:57-59](../../Sources/GraphiteUI/DrawingEditorDraftStore.swift#L57-L59)).
  5. The editor seeds its controller from `request.background` ([DrawingEditor.swift:126-127](../../Sources/GraphiteUI/DrawingEditor.swift#L126-L127)). The recovered drawing shows the original colour, and Insert or Done saves it with that colour.
- **Minimal fix:** In `editorRequest(inVaultAt:)`, pass `background: payload.background`. Then drop `background` from `DrawingEditorDraft`, keeping a decoder that ignores the old key.
- **Rule that prevents the class:** derived state as projections (the draft description repeats a field the payload owns, and the two copies drift apart)
- **Aliases:** none
- **Verifier notes:** No test covers recovery of a background (grep of `Tests/**` and `App/Tests/**` for draft/background found nothing). Recovery does not fix itself later either. A recovered editor that goes to the background again saves its draft from the recovered request, which holds the stale `draft.background` again. So the description never picks up the chosen colour.

#### BUG-INK-02 The shape shown while holding the Pencil is not what the stroke becomes when the canvas is zoomed
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Partly traced")
- **Reach:** iPad and iPhone (UIKit canvases). Normal path. "Make shapes on hold" is on by default ([StrokeHold.swift:41](../../Sources/GraphiteUI/StrokeHold.swift#L41)). The drawing editor's zoom is rarely 1: it is the view width over the canvas width ([DrawingEditor.swift:1096-1102](../../Sources/GraphiteUI/DrawingEditor.swift#L1096-L1102)), and a new canvas is 760 points wide ([DrawingEditor.swift:31](../../Sources/GraphiteUI/DrawingEditor.swift#L31)). Small strokes near the size thresholds are affected; large shapes are not.
- **Trigger:** On a zoomed canvas, draw a small circle or a short straight line and hold the Pencil at its end. For example, at zoom 3 a circle about 10 drawing points across.
- **Path:**
  1. `StrokeHoldRecognizer` is attached to the canvas itself ([HistoryCanvasView.swift:462-464](../../Sources/GraphiteUI/HistoryCanvasView.swift#L462-L464)). It records `touch.location(in: view)` and the coalesced samples ([StrokeHold.swift:91](../../Sources/GraphiteUI/StrokeHold.swift#L91), [StrokeHold.swift:97-99](../../Sources/GraphiteUI/StrokeHold.swift#L97-L99)). These points are in the scroll view's zoomed content coordinates. The code converts them itself in two places: dividing by `zoomScale` "from the canvas's coordinates to the drawing's" ([HistoryCanvasView.swift:522-523](../../Sources/GraphiteUI/HistoryCanvasView.swift#L522-L523)) and multiplying the preview line width by `zoomScale` ([HistoryCanvasView.swift:575](../../Sources/GraphiteUI/HistoryCanvasView.swift#L575)).
  2. At rest, `strokeTouchDidRest` runs `ShapeRecognizer.recognize` on those zoomed points and shows the preview ([HistoryCanvasView.swift:473-483](../../Sources/GraphiteUI/HistoryCanvasView.swift#L473-L483)).
  3. At lift, the `.overStroke` case only records `.awaitsItsShape` ([HistoryCanvasView.swift:516-518](../../Sources/GraphiteUI/HistoryCanvasView.swift#L516-L518)).
  4. When PencilKit reports the stroke, `drawingAfterShapeRecognition` removes the preview and calls `PencilShapes.replacingNewStroke` ([HistoryCanvasView.swift:345-346](../../Sources/GraphiteUI/HistoryCanvasView.swift#L345-L346), [HistoryCanvasView.swift:354-355](../../Sources/GraphiteUI/HistoryCanvasView.swift#L354-L355)). That recognizes again, from PencilKit's points interpolated every 3 points in drawing coordinates ([PencilShapes.swift:20-24](../../Sources/GraphiteApple/PencilShapes.swift#L20-L24)).
  5. The recognizer's limits are in absolute points: size at least 16 ([ShapeRecognizer.swift:199](../../Sources/GraphiteCore/ShapeRecognizer.swift#L199), [ShapeRecognizer.swift:231-232](../../Sources/GraphiteCore/ShapeRecognizer.swift#L231-L232)), a closing-gap floor of 6 ([ShapeRecognizer.swift:235](../../Sources/GraphiteCore/ShapeRecognizer.swift#L235)), a line deviation floor of 3 ([ShapeRecognizer.swift:250](../../Sources/GraphiteCore/ShapeRecognizer.swift#L250)), and an arc chord of at least 32 ([ShapeRecognizer.swift:218](../../Sources/GraphiteCore/ShapeRecognizer.swift#L218), [ShapeRecognizer.swift:267](../../Sources/GraphiteCore/ShapeRecognizer.swift#L267)). A stroke 42 points across on screen at zoom 3 is 14 points in the drawing. The hold accepts it and the lift rejects it, so the preview disappears and the wobbly stroke stays (`guard … else { return drawnDrawing }`, [HistoryCanvasView.swift:354-358](../../Sources/GraphiteUI/HistoryCanvasView.swift#L354-L358)).
- **Minimal fix:** Keep the shape recognized at the hold (converted to drawing coordinates, as the dragged case already does at [HistoryCanvasView.swift:523](../../Sources/GraphiteUI/HistoryCanvasView.swift#L523)). Apply it at the lift instead of recognizing a second time.
- **Rule that prevents the class:** decide-then-do (planner and executor): the decision shown to the user is the one executed
- **Aliases:** none
- **Verifier notes:** The two runs also differ at zoom 1. The hold uses raw touch samples and the lift uses points spaced 3 apart, so near a threshold they can disagree even unzoomed. The recognizer's doc comment says the thresholds are "relative to the stroke's size, so a shape is recognized the same way at any zoom" ([ShapeRecognizer.swift:194-196](../../Sources/GraphiteCore/ShapeRecognizer.swift#L194-L196)). The absolute floors above contradict it. The only hosted test feeds both paths the same coordinates (as the report says), so no test pins the opposite behaviour.

#### BUG-INK-03 Two quick taps on "Rotate Image Right" turn a drawing's picture once and leave two undo steps
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Partly traced")
- **Reach:** iPad and iPhone. Normal arranging path, but it depends on timing: the second tap must come during the first picture's decode and re-encode. Tapping twice for a half turn is a natural gesture.
- **Trigger:** Select a picture while arranging and tap Rotate Image Right twice quickly. The same race overwrites a move or resize made during the re-encode.
- **Path:**
  1. Each tap calls `runPictureChange`, which starts its own unowned `Task` ([DrawingEditor.swift:228](../../Sources/GraphiteUI/DrawingEditor.swift#L228), [DrawingEditor.swift:387-391](../../Sources/GraphiteUI/DrawingEditor.swift#L387-L391)). The button is disabled only when nothing is selected ([PDFPictureControls.swift:151](../../Sources/GraphiteUI/PDFPictureControls.swift#L151), [PDFPictureControls.swift:162](../../Sources/GraphiteUI/PDFPictureControls.swift#L162)), not while work runs.
  2. `rotateSelectedPictureRight` reads `placed` and its bytes, then awaits the detached re-encode ([DrawingEditor.swift:600-603](../../Sources/GraphiteUI/DrawingEditor.swift#L600-L603)). Both tasks therefore read the original picture.
  3. Each task computes the frame from the original ([DrawingEditor.swift:604-605](../../Sources/GraphiteUI/DrawingEditor.swift#L604-L605)) and calls `replacePicture` by identifier ([DrawingEditor.swift:606-607](../../Sources/GraphiteUI/DrawingEditor.swift#L606-L607), [DrawingEditor.swift:659-664](../../Sources/GraphiteUI/DrawingEditor.swift#L659-L664)). The second write replaces the first with an identical quarter turn.
  4. Each `replacePictures` registers one undo step ([DrawingEditor.swift:728-741](../../Sources/GraphiteUI/DrawingEditor.swift#L728-L741)). Result: a quarter turn instead of a half turn, and the first Undo restores an identical state, so it appears to do nothing.
- **Minimal fix:** Give the controller one picture operation at a time: a busy flag that disables the buttons, with a stored task that closing cancels. Apply the result to the current picture by identifier, or chain operations so each starts from the previous result.
- **Rule that prevents the class:** every task has an owner that cancels it, latest-answer-wins through one primitive
- **Aliases:** none
- **Verifier notes:** `cropSelectedPicture` has the same shape (read, await, replace; [DrawingEditor.swift:630-645](../../Sources/GraphiteUI/DrawingEditor.swift#L630-L645)). So a crop applied while a rotation is still running throws away the rotation, or the other way round. The PDF arrangement bar runs its actions through the same unowned-`Task` helper ([PDFPictureControls.swift:105](../../Sources/GraphiteUI/PDFPictureControls.swift#L105), [PDFPictureControls.swift:133-137](../../Sources/GraphiteUI/PDFPictureControls.swift#L133-L137)). I did not trace `PDFSession.rotatePictureRight`, so I make no claim about the PDF side.

#### BUG-INK-04 Drawing on a note's image says the note "no longer embeds" the image when the note only changed meanwhile
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "Traced")
- **Reach:** iPad and iPhone (the file is UIKit-only, [WorkspaceImageDrawing.swift:1](../../Sources/GraphiteUI/WorkspaceImageDrawing.swift#L1)). Race path. The editor is a full-screen cover, so the note can change only from another window of the same scene set, or from an external change applied during the save. Rare.
- **Trigger:** Save a drawing made on a note's image while the note's text changes during the link resolution that follows the file save.
- **Path:**
  1. `saveDrawingOnImage` writes the new file, then calls `replaceEmbeds` on the open session ([WorkspaceImageDrawing.swift:80-83](../../Sources/GraphiteUI/WorkspaceImageDrawing.swift#L80-L83)).
  2. `replaceEmbeds` snapshots `text` ([WorkspaceImageDrawing.swift:99](../../Sources/GraphiteUI/WorkspaceImageDrawing.swift#L99)), then awaits `isNameUnique` and one `resolveLink` per embed ([WorkspaceImageDrawing.swift:101](../../Sources/GraphiteUI/WorkspaceImageDrawing.swift#L101), [WorkspaceImageDrawing.swift:104-105](../../Sources/GraphiteUI/WorkspaceImageDrawing.swift#L104-L105)). Both suspend on the index ([WorkspaceModel.swift:661](../../Sources/GraphiteUI/WorkspaceModel.swift#L661), [WorkspaceModel.swift:988-991](../../Sources/GraphiteUI/WorkspaceModel.swift#L988-L991)).
  3. If the text changed, the guard returns `0` ([WorkspaceImageDrawing.swift:114-115](../../Sources/GraphiteUI/WorkspaceImageDrawing.swift#L114-L115)). That is the same value as "no embed found".
  4. The caller shows "…the note no longer embeds “…”, so nothing in it changed" ([WorkspaceImageDrawing.swift:84-86](../../Sources/GraphiteUI/WorkspaceImageDrawing.swift#L84-L86)). The note still embeds the image and still shows the original. The new drawing exists unreferenced, and the message gives a false cause.
- **Minimal fix:** Return an outcome (`.replaced(n)`, `.noEmbed`, `.textChanged`). On `.textChanged`, retry once against the current text, or report that the note changed during the save.
- **Rule that prevents the class:** outcomes as return values
- **Aliases:** none
- **Verifier notes:** The report's trigger mentions "an autosaved edit". Autosave does not change `session.text`, so it does not trigger this. The real triggers are typing in another window and an external change reloaded into the session. Nothing is lost: the drawing file is saved and the user can embed it by hand.

### LECTURE

#### BUG-LECTURE-01 One lecture whose save failed is offered again as a second recording and can be saved twice
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Traced")
- **Reach:** iPad, iPhone and Mac. Failure path only: the destination folder is removed or renamed during the recording, or the name gets taken. After such a failure, a duplicate offer follows every vault open, every relaunch, and every other recovery or discard ([WorkspaceRecordingRecovery.swift:36](../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L36), [WorkspaceRecordingRecovery.swift:41](../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L41)).
- **Trigger:** An audio recording stops and publication fails. Then the vault is opened again (or the app is relaunched), the user saves the offered recording, and later uses Try Saving Again.
- **Path:**
  1. `finish` calls `saveAsM4A(X.caf)` ([RecordingController.swift:307](../../Sources/GraphiteApple/RecordingController.swift#L307)). `convertedToM4A` exports `X.m4a` next to it ([RecordingController.swift:382-394](../../Sources/GraphiteApple/RecordingController.swift#L382-L394)).
  2. `publish` throws for a missing folder or a taken name ([RecordingController.swift:14-16](../../Sources/GraphiteApple/RecordingController.swift#L14-L16), [RecordingController.swift:21-23](../../Sources/GraphiteApple/RecordingController.swift#L21-L23)) before its own removal at [RecordingController.swift:27](../../Sources/GraphiteApple/RecordingController.swift#L27). Line 372 never runs. `finish` sets `.failed` and keeps `recoveryURL = X.caf` ([RecordingController.swift:310-313](../../Sources/GraphiteApple/RecordingController.swift#L310-L313)). `X.m4a` stays in the recovery folder.
  3. Leaving the vault is allowed in `.failed` ([WorkspaceModel.swift:262](../../Sources/GraphiteUI/WorkspaceModel.swift#L262), [RecordingState.swift:8](../../Sources/GraphiteCore/RecordingState.swift#L8)). `openVault` calls `checkForUnfinishedRecordings` ([WorkspaceModel.swift:343](../../Sources/GraphiteUI/WorkspaceModel.swift#L343)), whose guard passes in `.failed` ([WorkspaceRecordingRecovery.swift:16-18](../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L16-L18)).
  4. `unfinishedRecordings` excludes only `X.caf` ([RecordingController.swift:351-354](../../Sources/GraphiteApple/RecordingController.swift#L351-L354)). `recordings(in:excluding:)` accepts `X.m4a`: `m4a` is a recovery extension, the file is over 4096 bytes, and it is not a later part ([RecordingRecovery.swift:50](../../Sources/GraphiteCore/RecordingRecovery.swift#L50), [RecordingRecovery.swift:126-141](../../Sources/GraphiteCore/RecordingRecovery.swift#L126-L141)). Its manifest location is `X.json`, the original's ([RecordingRecovery.swift:59-61](../../Sources/GraphiteCore/RecordingRecovery.swift#L59-L61), [RecordingRecovery.swift:147](../../Sources/GraphiteCore/RecordingRecovery.swift#L147)), so the vault filter keeps it ([WorkspaceRecordingRecovery.swift:7-12](../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L7-L12)).
  5. Save to Vault runs `recover` ([WorkspaceRecordingRecovery.swift:23-31](../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L23-L31)), then `saveAsM4A(X.m4a)` with `converted == source` ([RecordingController.swift:359-361](../../Sources/GraphiteApple/RecordingController.swift#L359-L361), [RecordingController.swift:381](../../Sources/GraphiteApple/RecordingController.swift#L381)). The lecture is published and `X.json` is removed ([RecordingController.swift:373](../../Sources/GraphiteApple/RecordingController.swift#L373)).
  6. The toolbar still offers Try Saving Again for `X.caf` ([RecordingControls.swift:43-44](../../Sources/GraphiteUI/RecordingControls.swift#L43-L44)). `retryRecordingPublication` picks a fresh unique path ([WorkspaceModel.swift:1148-1165](../../Sources/GraphiteUI/WorkspaceModel.swift#L1148-L1165)) and `finish` publishes the same lecture again ([RecordingController.swift:401-407](../../Sources/GraphiteApple/RecordingController.swift#L401-L407)). The vault now holds two M4A files of one lecture.
- **Minimal fix:** Treat `X.m4a` as part of `X.caf`'s recording: `recordings(in:)` should skip an `.m4a` whose `.caf` sibling exists. Alternatively, `saveAsM4A` should delete the converted file when publication throws, so the conversion is redone on retry.
- **Rule that prevents the class:** one owner per business rule (what files belong to one recording is known only to `discardRecoveredRecording`, [RecordingController.swift:421-428](../../Sources/GraphiteApple/RecordingController.swift#L421-L428))
- **Aliases:** none
- **Verifier notes:** The relaunch variant holds too. With the controller idle, nothing is excluded, so both `X.caf` and `X.m4a` are listed with the same manifest and offered one after the other. Saving `X.m4a` first deletes `X.json`. `X.caf` is then offered without a destination and saved as "Recovered recording …" ([WorkspaceRecordingRecovery.swift:27-28](../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L27-L28)). Tests adopt a lone `.m4a` recovery file ([AppleRecordingAccessFixTests.swift:30](../../Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift#L30)) and never create the `.caf` + `.m4a` pair, so nothing pins this.

#### BUG-LECTURE-02 A digitally signed PDF embedded in a note says it is password protected
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "Traced")
- **Reach:** iPad, iPhone and Mac (the banner is not platform-gated; the Annotate button exists only with UIKit). Normal path for every signed, unencrypted PDF embedded in a note.
- **Trigger:** Embed a signed but unencrypted PDF (`![[signed.pdf]]`) and view the note.
- **Path:**
  1. `isProtected` is `isPasswordProtected || (hasDigitalSignatures && !acceptsSignatureInvalidation)` ([PDFSession.swift:339](../../Sources/GraphiteUI/PDFSession.swift#L339)). For a signed file `isPasswordProtected` is false ([PDFSession.swift:346](../../Sources/GraphiteUI/PDFSession.swift#L346)), but `isProtected` is true.
  2. The embed's banner checks `isProtected` and shows "This PDF is protected by a password…" ([EmbeddedPDFViewer.swift:262-263](../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L262-L263)).
  3. `canStartAnnotating` is false ([EmbeddedPDFViewer.swift:283-286](../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L283-L286)), so Annotate is disabled ([EmbeddedPDFViewer.swift:189](../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L189)). The only setter of `acceptsSignatureInvalidation` is in the pane ([PDFPane.swift:283](../../Sources/GraphiteUI/PDFPane.swift#L283)). The pane tells the two cases apart and offers Edit Anyway ([PDFPane.swift:304-319](../../Sources/GraphiteUI/PDFPane.swift#L304-L319)).
- **Minimal fix:** In the embed banner, branch as the pane does: show the password text only when `isPasswordProtected`, and the signature text otherwise. Share one banner model between the pane and the embed.
- **Rule that prevents the class:** flows as enums, not booleans (`isProtected` merges two reasons that need different wording and different remedies)
- **Aliases:** none
- **Verifier notes:** I confirmed that no embedded path sets `acceptsSignatureInvalidation` (it has a single writer). The user can recover by opening the full PDF view, which explains the signature.

#### BUG-LECTURE-03 The embedded viewer's page field rejects page numbers typed in non-ASCII digits
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "Partly traced")
- **Reach:** iPad, iPhone and Mac. Normal path for people whose keyboard types Arabic-Indic, Persian, Devanagari or full-width digits.
- **Trigger:** Type "٣" (or "３") in the page field of an embedded PDF and submit or leave the field.
- **Path:**
  1. Submitting, or leaving the field after typing, calls `goToTypedPage` ([EmbeddedPDFViewer.swift:229-235](../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L229-L235), [EmbeddedPDFViewer.swift:361-368](../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L361-L368)).
  2. It parses with `Int(String)` ([EmbeddedPDFViewer.swift:372](../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L372)). The standard library's `Int.init?(_ description: String)` accepts only ASCII `0`–`9` after an optional sign, so it returns nil.
  3. The field is reset to the current page with no message ([EmbeddedPDFViewer.swift:373-374](../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L373-L374)). The pane's Go to Page parser accepts any decimal digit by design ([PDFPane.swift:545-558](../../Sources/GraphiteUI/PDFPane.swift#L545-L558)).
- **Minimal fix:** Call `GoToPage…pageNumber(from:pageCount:)` (the static parser at [PDFPane.swift:548](../../Sources/GraphiteUI/PDFPane.swift#L548)) from `goToTypedPage`, or move it to one shared helper.
- **Rule that prevents the class:** one owner per business rule (page-number parsing exists twice and the copies disagree)
- **Aliases:** none
- **Verifier notes:** No test exercises either parser (grep for `pageNumber(from:` and `goToTypedPage` in tests found nothing). The claim that these keyboards type native digits comes from the code's own comment ([PDFPane.swift:545-547](../../Sources/GraphiteUI/PDFPane.swift#L545-L547)). The `Int` rejection is standard-library behaviour.

#### BUG-LECTURE-04 On the Mac, "Open Settings" for a denied microphone opens the camera privacy pane
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "Traced")
- **Reach:** Mac only. Permission-denied path for video recording (camera allowed, microphone denied or restricted).
- **Trigger:** On a Mac with microphone access denied, choose Record Video, then Open Settings in the recording menu.
- **Path:**
  1. `CameraCaptureSource.start` passes the camera check and then throws `.microphoneDenied` from `requireAccess(to: .audio…)` ([CameraCaptureSource.swift:46-47](../../Sources/GraphiteApple/CameraCaptureSource.swift#L46-L47), [CameraCaptureSource.swift:117-124](../../Sources/GraphiteApple/CameraCaptureSource.swift#L117-L124)).
  2. `startVideo` stores it: `accessProblem = error as? CaptureAccessProblem` ([RecordingController.swift:497](../../Sources/GraphiteApple/RecordingController.swift#L497)).
  3. `canBeChangedInSettings` is true for it ([VideoCapture.swift:66-70](../../Sources/GraphiteApple/VideoCapture.swift#L66-L70)), so the menu shows Open Settings, which opens `RecordingControlModel.settingsLocation` ([RecordingControls.swift:35-37](../../Sources/GraphiteUI/RecordingControls.swift#L35-L37)).
  4. On macOS that URL is always `…?Privacy_Camera` ([RecordingControls.swift:107-112](../../Sources/GraphiteUI/RecordingControls.swift#L107-L112)), so System Settings opens on Camera.
- **Minimal fix:** Make `settingsLocation` a function of the `CaptureAccessProblem`: `Privacy_Microphone` for the microphone cases, `Privacy_Camera` for the camera cases.
- **Rule that prevents the class:** typed errors, one presenter (the remedy should come from the typed error it answers)
- **Aliases:** none
- **Verifier notes:** `.microphoneRestricted` takes the same path. On iPad and iPhone the URL opens Graphite's own settings page, which has both switches, so only the Mac is affected.

### VOICE

#### BUG-VOICE-01 Stop in the floating player between two PDF pages does not stop: the next page starts reading
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Traced")
- **Reach:** iPad, iPhone and Mac. Normal multi-page PDF reading with the floating player. The window lasts as long as the next page's text preparation, which is short for text pages.
- **Trigger:** While a PDF page range is read, tap Stop in the floating player after one page ends and before the next is ready.
- **Path:**
  1. The last passage ends. `finishCurrentPassage` sets `.finished` and calls `didFinishDocument` ([ReadAloudSpeech.swift:836-838](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L836-L838)), which is `continuePDFIfNeeded` ([ReadAloudController.swift:93](../../Sources/GraphiteUI/ReadAloudController.swift#L93)).
  2. `continuePDFIfNeeded` runs the stored continuation ([ReadAloudController.swift:447-451](../../Sources/GraphiteUI/ReadAloudController.swift#L447-L451)), which calls `loadPDFPage(…, playsWhenReady: true)` ([ReadAloudController.swift:713-714](../../Sources/GraphiteUI/ReadAloudController.swift#L713-L714)). That captures the current `preparationIdentifier`, sets `isPreparing` and starts the page task ([ReadAloudController.swift:633-654](../../Sources/GraphiteUI/ReadAloudController.swift#L633-L654)).
  3. Stop stays enabled because the previous page's document is still loaded ([ReadAloudFloatingPlayer.swift:222-225](../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L222-L225)). `stopAndRewind` calls only `session.stop()` and `session.move(to: 0)` ([ReadAloudNavigator.swift:174-178](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L174-L178)). It never reaches `ReadAloudController.stop`, which clears `preparationIdentifier` and cancels `preparation` ([ReadAloudController.swift:414-422](../../Sources/GraphiteUI/ReadAloudController.swift#L414-L422)).
  4. The page task's identifier checks pass ([ReadAloudController.swift:660](../../Sources/GraphiteUI/ReadAloudController.swift#L660), [ReadAloudController.swift:684](../../Sources/GraphiteUI/ReadAloudController.swift#L684)). `finishPreparing` loads the page ([ReadAloudController.swift:718](../../Sources/GraphiteUI/ReadAloudController.swift#L718), [ReadAloudController.swift:725](../../Sources/GraphiteUI/ReadAloudController.swift#L725)), and `playsWhenReady && recognition == nil && state != .speaking` calls `session.play()` ([ReadAloudController.swift:719](../../Sources/GraphiteUI/ReadAloudController.swift#L719)). The next page starts reading.
- **Minimal fix:** Have `stopAndRewind` call `reader.stop()`, which also cancels preparation and the continuation, before rewinding. Otherwise route every Stop through one controller method.
- **Rule that prevents the class:** every task has an owner that cancels it, latest-answer-wins through one primitive
- **Aliases:** none (shares a root cause with BUG-VOICE-02: Stop in the player bypasses the controller that owns the tasks)
- **Verifier notes:** I disagree with the report's scanned-page remark. For a page that needs text recognition, line 719 does not play (`snapshot.recognition == nil` is false), and `finishPreparing` withholds play for review ([ReadAloudController.swift:727](../../Sources/GraphiteUI/ReadAloudController.swift#L727)). So a scanned next page does not start after Stop: it loads silently. The defect is limited to pages with a text layer. No test covers `stopAndRewind` (grep found none).

#### BUG-VOICE-V01 A pronunciation file that fails to read or parse is replaced by the one entry added in Settings
- **Verdict:** Confirmed
- **Severity:** High
- **Reach:** iPad, iPhone and Mac. Fallback path: the vault's `.graphite/pronunciations.json` is unreadable or unparseable when Settings opens. Causes include a hand edit that leaves invalid JSON (for example a file cut off before its closing brace; Apple's JSON parser accepts a trailing comma, so that case loads fully), a file over 256 KiB, or a read error such as a cloud file that is not downloaded. When it happens, the loss is total and has no undo.
- **Trigger:** A user hand-edits the pronunciation file and leaves a syntax error, then opens Settings › Read Aloud › Pronunciations. The vault section is empty, so they add one term.
- **Path:**
  1. `load` turns every failure into an empty list. `Data(contentsOf:)` failing gives `entries = []` ([ReadAloudPronunciationEditor.swift:96](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L96)). `vaultEntries` returns `[]` for a file over the size limit or for JSON that does not parse ([ReadAloudPronunciations.swift:63-64](../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L63-L64)).
  2. Adding a term builds `updated` from the empty `entries` plus the new pair ([ReadAloudPronunciationEditor.swift:36-39](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L36-L39)).
  3. `save` writes only that pair over the file, atomically ([ReadAloudPronunciationEditor.swift:101-107](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L101-L107)). Every hand-written entry is replaced without a warning.
- **Minimal fix:** Make `load` tell "no file" apart from "file present but unreadable or invalid". In the second case, show the error and disable editing (or move the old file aside to `pronunciations.json.bak` before writing).
- **Rule that prevents the class:** failed reads are never empty results
- **Aliases:** none (related to BUG-VOICE-10: same editor, same read-modify-write, but a different trigger and the whole file lost)
- **Verifier notes:** The reports missed this. The editor's own comment says "a failure keeps the old file" ([ReadAloudPronunciationEditor.swift:100](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L100)), but that covers only a failed write; a failed read leads to the overwrite. Reading uses an uncoordinated `Data(contentsOf:)` rather than the vault store. I rate it High rather than Critical because it needs a malformed or unreadable file first. Under that condition the user's file is destroyed by an ordinary Add.

#### BUG-VOICE-L01 Saving the pronunciation list drops every term past the first 2,000 read from the file
- **Verdict:** Confirmed
- **Severity:** Low
- **Reach:** iPad, iPhone and Mac; a vault pronunciation file with more than 2,000 terms (rare); normal Settings path.
- **Trigger:** the vault's `.graphite/pronunciations.json` holds more than 2,000 terms; the person adds or edits one term in Settings › Read Aloud › Pronunciations.
- **Path:** `vaultEntries` keeps `entries.prefix(2_000)` of a `[String: Any]` dictionary, whose order is unspecified ([ReadAloudPronunciations.swift:63-66](../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L63-L66)) → `load` stores only those ([ReadAloudPronunciationEditor.swift:95-98](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L95-L98)) → adding a term writes `entries` plus the new term over the whole file ([ReadAloudPronunciationEditor.swift:36-39](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L36-L39), [101-107](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L101-L107)) → an arbitrary set of terms beyond 2,000 is gone.
- **Minimal fix:** the editor refuses to save (and says why) when the file holds more terms than it loaded; the cap applies to speech lookup only.
- **Rule that prevents the class:** failed reads are never empty results (a partial read is never written back as the whole)
- **Aliases:** none (same read-modify-write as BUG-VOICE-V01 and BUG-VOICE-10)
- **Verifier notes:** found by the lead while re-checking BUG-VOICE-V01.

#### BUG-VOICE-02 Stop in the floating player while a fold change is being prepared restarts reading
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "Traced")
- **Reach:** iPad, iPhone and Mac. Notes with folds, while reading. The window is the time to re-prepare the note, which is longer for large notes or when math is involved. Rare.
- **Trigger:** While a note is read aloud, fold or unfold a heading or callout, then tap Stop before the re-preparation finishes.
- **Path:**
  1. `MarkdownPane` calls `foldsDidChange` on a fold change ([MarkdownPane.swift:127-130](../../Sources/GraphiteUI/MarkdownPane.swift#L127-L130)).
  2. `foldsDidChange` captures `wasSpeaking = true` ([ReadAloudController.swift:127](../../Sources/GraphiteUI/ReadAloudController.swift#L127)), sets `foldPreparationIdentifier`, and starts a task that nothing stores or cancels ([ReadAloudController.swift:130-136](../../Sources/GraphiteUI/ReadAloudController.swift#L130-L136)).
  3. Stop runs `stopAndRewind` ([ReadAloudNavigator.swift:174-178](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L174-L178)), which changes neither `foldPreparationIdentifier` nor `markdownRequest`.
  4. The task's guard passes ([ReadAloudController.swift:141](../../Sources/GraphiteUI/ReadAloudController.swift#L141)). It calls `load`, `move` and, because of the captured flag, `play()` ([ReadAloudController.swift:145-147](../../Sources/GraphiteUI/ReadAloudController.swift#L145-L147)). Reading resumes by itself.
- **Minimal fix:** Store the fold task in `preparation`, or give it its own owned task, and cancel it from `ReadAloudController.stop()` and `clear()`. Check, after the await, that no stop happened (`stopIdentifier` unchanged) before playing.
- **Rule that prevents the class:** every task has an owner that cancels it, latest-answer-wins through one primitive
- **Aliases:** none
- **Verifier notes:** `ReadAloudController.stop()` does not stop this task either: it does not touch `foldPreparationIdentifier` ([ReadAloudController.swift:414-422](../../Sources/GraphiteUI/ReadAloudController.swift#L414-L422)). That widens the trigger. Starting a lecture recording calls `readAloud.stop()` ([WorkspaceModel.swift:1114](../../Sources/GraphiteUI/WorkspaceModel.swift#L1114), [GraphiteRootView.swift:127-129](../../Sources/GraphiteUI/GraphiteRootView.swift#L127-L129)). A fold task still pending then calls `play()` during the recording, and the speech adapter sets the audio category to `.playback` ([ReadAloudSpeech.swift:281-287](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L281-L287)) over the recorder's `.playAndRecord` ([RecordingController.swift:180-183](../../Sources/GraphiteApple/RecordingController.swift#L180-L183)). Reading cannot settle what that does to the running recorder. `clear()` does defeat the task, because it sets `markdownRequest = nil` and the guard then fails.

#### BUG-VOICE-03 Every sentence skip, passage jump and PDF page break gives up and retakes the audio session, contrary to the documented contract
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Traced")
- **Reach:** iPad and iPhone for session deactivation (the `#if os(iOS)` blocks). On the Mac, the neural adapter stops and restarts its `AVAudioEngine`. Normal path, at every skip, section jump and page break.
- **Trigger:** While reading, tap Next or Previous Sentence, jump to a section, or let reading cross to the next PDF page.
- **Path:**
  1. Skip: `moveToNextSentence` → `seek` ([ReadAloudSpeech.swift:615-618](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L615-L618)) → `stop()` ([ReadAloudSpeech.swift:653-656](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L653-L656)). `move(to:)` also calls `stop()` ([ReadAloudSpeech.swift:596-599](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L596-L599)).
  2. Page break: the continuation reaches `finishPreparing` → `session.load` ([ReadAloudController.swift:725](../../Sources/GraphiteUI/ReadAloudController.swift#L725)) → `stop()` ([ReadAloudSpeech.swift:545-546](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L545-L546)). This undoes the "keep audio" answer that `didFinishDocument` gave a moment earlier ([ReadAloudSpeech.swift:838](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L838), documented at [ReadAloudSpeech.swift:439-441](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L439-L441)).
  3. `stop()` calls `speech.releaseAudio()` ([ReadAloudSpeech.swift:582-584](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L582-L584)).
  4. The Apple adapter deactivates with `.notifyOthersOnDeactivation` ([ReadAloudSpeech.swift:296-304](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L296-L304)). The neural adapter forwards that, shuts the engine down, and deactivates ([NeuralReadAloudSpeech.swift:245-254](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L245-L254), [RenderedPassagePlayer.swift:87-90](../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L87-L90)).
  5. `speakCurrentPassage` → `speak` → `activateAudioSession` activates again, because `ownsActiveAudioSession` is now false ([ReadAloudSpeech.swift:251-252](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L251-L252), [ReadAloudSpeech.swift:281-288](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L281-L288), [NeuralReadAloudSpeech.swift:162](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L162), [NeuralReadAloudSpeech.swift:259-266](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L259-L266)).
- **Minimal fix:** Split `stop()` into an internal "invalidate the utterance" step, used by `seek`, `move` and `load`, and the public Stop that also releases audio. Release only on the user's Stop, on clear, and on finish without continuation.
- **Rule that prevents the class:** one owner per business rule (one owner of the audio-session lifetime policy; today every navigation helper decides it by calling `stop()`)
- **Aliases:** none
- **Verifier notes:** The test named for this contract does not catch it. It reads `releasesWhileContinuing` after the finish but before `load`, then asserts only `XCTAssertGreaterThan` after a later finish ([ReadAloudSessionTests.swift:279-291](../../Tests/GraphiteAppleTests/ReadAloudSessionTests.swift#L279-L291)). The release inside `load` at line 287 is therefore never checked. The audible effect depends on the other app. One that was interrupted and resumes on `notifyOthersOnDeactivation` gets a resume and a new interruption at every skip. Whether reactivating from the background after a page break fails when another app holds a non-mixable session is platform behaviour that reading cannot settle.

#### BUG-VOICE-04 High Quality plays faster speeds at 1.5× while the controls show the chosen speed
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Traced")
- **Reach:** iPad, iPhone and Mac. High Quality mode, which is the default once a voice is downloaded. Every passage read at 1.75× to 3×.
- **Trigger:** In High Quality mode, choose 2× in the floating player, the popover or Settings.
- **Path:**
  1. The pickers offer 0.75× to 3× ([ReadAloudVoiceSettings.swift:19](../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L19), [ReadAloudFloatingPlayer.swift:250-251](../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L250-L251), [ReadAloudControls.swift:118-119](../../Sources/GraphiteUI/ReadAloudControls.swift#L118-L119)). None of them filters by mode.
  2. `setSpeed` accepts values up to 3 ([ReadAloudSpeech.swift:446](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L446), [ReadAloudSpeech.swift:688-693](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L688-L693)), and the utterance request carries the value ([ReadAloudSpeech.swift:738-739](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L738-L739)).
  3. `NeuralReadAloudSpeech.start` passes `request.speed` to `player.play(rate:)` ([NeuralReadAloudSpeech.swift:168](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L168)), which clamps the time-pitch rate to 0.5…1.5 ([RenderedPassagePlayer.swift:24](../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L24), [RenderedPassagePlayer.swift:39](../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L39)). The label says 2× and the audio plays at 1.5×.
- **Minimal fix:** Widen the clamp to the session's `speedRange` (`AVAudioUnitTimePitch` accepts rates far beyond 3). Otherwise offer only the speeds the active adapter supports, taken from the adapter.
- **Rule that prevents the class:** contract test suites shared by every implementation (the two `ReadAloudSpeaking` adapters disagree on the speed range)
- **Aliases:** none
- **Verifier notes:** The leading pause is still divided by the chosen speed ([ReadAloudSpeech.swift:730](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L730)), so pauses shrink while the voice stays at 1.5×. `setRate` has the same clamp ([RenderedPassagePlayer.swift:65-67](../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L65-L67)).

#### BUG-VOICE-05 Under VoiceOver, Speak Selection or Speak Screen, High Quality reading has no working speed control
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Traced")
- **Reach:** iPad and iPhone (the property is false on the Mac, [ReadAloudSpeech.swift:206-211](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L206-L211)). High Quality mode with an assistive speech feature on and the default "follow system voice" choice. Every reading by these users.
- **Trigger:** Turn on VoiceOver (or Speak Selection or Speak Screen), leave Voice on the system voice, and read in High Quality mode.
- **Path:**
  1. `speedFollowsSystem = followsSystemVoice && speech.assistiveSpeechSettingsMayApply` ([ReadAloudSpeech.swift:507](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L507)). The neural adapter forwards the system adapter's answer ([NeuralReadAloudSpeech.swift:59](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L59)), so it is true.
  2. Settings hides the speed picker ([ReadAloudVoiceSettings.swift:56](../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L56)). The popover shows "Speed follows … Speaking Rate" instead ([ReadAloudControls.swift:109-112](../../Sources/GraphiteUI/ReadAloudControls.swift#L109-L112)). The floating player disables its menu ([ReadAloudFloatingPlayer.swift:266](../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L266)).
  3. Rendered audio plays at `request.speed`, the stored Graphite speed ([NeuralReadAloudSpeech.swift:168](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L168)). `usesSystemSettings` takes effect only on the system voice ([ReadAloudSpeech.swift:272](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L272)). The UI says the system rate applies, but the stored speed is used and cannot be changed.
- **Minimal fix:** Have the neural adapter report `assistiveSpeechSettingsMayApply = false` while it reads with a downloaded voice (`readsWithDownloadedVoice`), so the speed control comes back.
- **Rule that prevents the class:** contract test suites shared by every implementation (the adapter forwards a property whose meaning it does not honour)
- **Aliases:** none
- **Verifier notes:** Speed is also inconsistent within one reading. A passage that High Quality hands to the system voice (unprepared, or rejected by the render check, [NeuralReadAloudSpeech.swift:87-96](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L87-L96)) plays at the system Speaking Rate. Rendered passages play at the stored speed. The user's only escape is to choose a specific voice in the Voice picker.

#### BUG-VOICE-06 A voice download's failure reason is replaced by "Paused" moments after it is shown
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "Traced")
- **Reach:** iPad, iPhone and Mac. Voice-download failure path only: a non-2xx answer, a checksum mismatch, or a failed move.
- **Trigger:** A voice file download finishes with HTTP 404 (for example, a removed revision) or fails its checksum.
- **Path:**
  1. `didFinishDownloadingTo` reports `.failed(…)` and returns ([NeuralVoiceDownloader.swift:162-164](../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L162-L164), [NeuralVoiceDownloader.swift:173-175](../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L173-L175), [NeuralVoiceDownloader.swift:178-182](../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L178-L182)).
  2. URLSession then calls `didCompleteWithError` with `nil`, because the transport succeeded. That runs `installIfCompleteWhenIdle` ([NeuralVoiceDownloader.swift:187-191](../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L187-L191)), which, once no task of the voice is running, calls `installIfComplete` ([NeuralVoiceDownloader.swift:264-269](../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L264-L269)).
  3. The failed file is not staged, so `complete` is false and `reportPaused` runs ([NeuralVoiceDownloader.swift:276-282](../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L276-L282)).
  4. The library keeps the last state it received ([NeuralVoiceLibrary.swift:188-189](../../Sources/GraphiteVoices/NeuralVoiceLibrary.swift#L188-L189)). The row shows "Paused" with Resume instead of the red message ([NeuralVoiceSettings.swift:154-161](../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L154-L161), [NeuralVoiceSettings.swift:173-176](../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L173-L176)).
- **Minimal fix:** Record failed files per voice in the downloader. Have `installIfComplete` report the stored failure instead of `.paused` when one exists, and clear it when a new download starts.
- **Rule that prevents the class:** derived state as projections (the voice's state should be computed from its files' outcomes, not be the last message that arrived)
- **Aliases:** none
- **Verifier notes:** When other files of the same voice are still running, the paused report waits until the last of them completes, but it does arrive. The failure is overwritten either way. The delegate order (finish-downloading, then complete) is URLSession's documented sequence for a download task that received a response.

#### BUG-VOICE-07 Closing reading, choosing Quick, deleting the voice or leaving the app mid-render keeps the neural model in memory
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Traced")
- **Reach:** iPad, iPhone and Mac, on devices (the Simulator never loads a model, [NeuralSpeechEngine.swift:80-81](../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L80-L81)). High Quality mode. It happens whenever reading is closed, or the app resigns active, before the queue finishes rendering. That is common, because rendering runs ahead through the whole document.
- **Trigger:** Close the reader, switch to Quick, delete the selected voice, or switch apps while passages are still rendering.
- **Path:**
  1. The triggers reach `ReadAloudPassagePreparation.cancel` or `suspend`. Close: `ReadAloudController.clear` → `session.clear` → `speech.cancelPreparation()` ([ReadAloudController.swift:424-425](../../Sources/GraphiteUI/ReadAloudController.swift#L424-L425), [ReadAloudSpeech.swift:594](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L594), [NeuralReadAloudSpeech.swift:137-139](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L137-L139)). Quick or delete: the settings views cancel directly ([NeuralVoiceSettings.swift:16](../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L16), [NeuralVoiceSettings.swift:91](../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L91)). Resign active: `suspend()` ([ReadAloudVoices.swift:24-26](../../Sources/GraphiteUI/ReadAloudVoices.swift#L24-L26)).
  2. Both cancel the worker task ([ReadAloudPassagePreparation.swift:143-148](../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L143-L148), [ReadAloudPassagePreparation.swift:157-159](../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L157-L159)).
  3. `renderQueue` returns at `guard !Task.isCancelled else { return }` ([ReadAloudPassagePreparation.swift:213](../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L213)), before `renderer.releaseResources()` ([ReadAloudPassagePreparation.swift:220](../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L220)).
  4. `NeuralSpeechEngine.loaded` keeps the model until another queue completes or another voice loads ([NeuralSpeechEngine.swift:78-79](../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L78-L79), [NeuralSpeechEngine.swift:111-115](../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L111-L115)). No other caller unloads it: grep for `releaseResources()` and `.unload()` finds only these and the benchmark, and there is no memory-warning hook in this module.
- **Minimal fix:** In `cancel()`, and in `suspend()` (iOS refuses GPU work in the background anyway), call `renderer.releaseResources()` once the cancelled worker has ended. Alternatively, put the release in a `defer` inside `renderQueue`, so it runs on every exit.
- **Rule that prevents the class:** cleanup runs on every exit path, cancellation included (a `defer` next to the acquisition). New rule: none of the listed rules covers it.
- **Aliases:** none
- **Verifier notes:** I disagree with the report on Stop. The floating player's Stop (`stopAndRewind`) and `ReadAloudController.stop()` do not cancel preparation ([ReadAloudNavigator.swift:174-178](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L174-L178), [ReadAloudController.swift:414-422](../../Sources/GraphiteUI/ReadAloudController.swift#L414-L422)). After Stop, rendering runs to the end and then releases the model normally. So Stop is not a trigger; Close is. After `suspend`, the model is released once the app returns and the resumed queue completes ([ReadAloudPassagePreparation.swift:150-154](../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L150-L154)). The memory is held exactly while the app is in the background, which is when iOS ends memory-heavy apps first. The figure of 0.25–3 GB is the code's own comment ([ReadAloudPassagePreparation.swift:218-219](../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L218-L219)).

#### BUG-VOICE-08 Unplugging headphones during High Quality reading does not pause it
- **Verdict:** Confirmed (no pause reaches the session); Plausible (what the user hears)
- **Severity:** Medium  (reported: none given; "Partly traced")
- **Reach:** iPad and iPhone with wired or Bluetooth outputs. High Quality mode. Every disconnect while reading.
- **Trigger:** In High Quality mode, while a rendered passage plays, disconnect the headphones.
- **Path:**
  1. Only the system-voice adapter handles `routeChangeNotification` with `.oldDeviceUnavailable` ([ReadAloudSpeech.swift:375-390](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L375-L390)). It sends `.interrupted` only if its own `activeUtterance` is set ([ReadAloudSpeech.swift:387](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L387)). During rendered playback it has no utterance, and the neural adapter would drop its events anyway, because `routesToQuick` is false ([NeuralReadAloudSpeech.swift:41-44](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L41-L44)).
  2. `NeuralReadAloudSpeech` observes only `interruptionNotification` ([NeuralReadAloudSpeech.swift:45-51](../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L45-L51)), and `RenderedPassagePlayer` observes nothing ([RenderedPassagePlayer.swift:19-22](../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L19-L22)). No `.interrupted` event reaches `ReadAloudSession.receive` ([ReadAloudSpeech.swift:761-769](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L761-L769)), so the session stays `.speaking`.
- **Minimal fix:** In `NeuralReadAloudSpeech`, observe `routeChangeNotification` (`.oldDeviceUnavailable`) and `AVAudioEngineConfigurationChange` the same way it handles an interruption: `stop()`, then `eventHandler?(.interrupted)`.
- **Rule that prevents the class:** contract test suites shared by every implementation (both adapters must turn a lost output into `.interrupted`)
- **Aliases:** none
- **Verifier notes:** Reading cannot settle what the user hears. It depends on whether `AVAudioEngine` stops itself on the route change, which it does when the output's format changes. If it keeps running, the lecture plays out loud through the speaker. If it stops, the `.dataPlayedBack` completion ([RenderedPassagePlayer.swift:47-53](../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L47-L53)) may not fire, and the session stays in `.speaking` with no sound. A device test (play rendered audio over AirPods, then disconnect) settles it. Either outcome is wrong.

#### BUG-VOICE-09 Folding or unfolding while reading restarts the current passage from its first word
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given; "Traced")
- **Reach:** iPad, iPhone and Mac. Notes with folds, while reading. Repeats up to one passage.
- **Trigger:** While a passage is read, fold or unfold a section elsewhere in the note.
- **Path:**
  1. `foldsDidChange` records the source location being read ([ReadAloudController.swift:128-129](../../Sources/GraphiteUI/ReadAloudController.swift#L128-L129)) and, after re-preparing, picks the passage containing it ([ReadAloudController.swift:142-144](../../Sources/GraphiteUI/ReadAloudController.swift#L142-L144)).
  2. `session.load` calls `stop()`, which leaves state `.idle` and offset 0 ([ReadAloudSpeech.swift:545-546](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L545-L546), [ReadAloudSpeech.swift:582-591](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L582-L591)). Then `session.move(to: resumeIndex)` ([ReadAloudController.swift:146](../../Sources/GraphiteUI/ReadAloudController.swift#L146)) calls `stop()` again and sets `.paused` and `needsRestart` ([ReadAloudSpeech.swift:596-603](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L596-L603)).
  3. `play()` ([ReadAloudController.swift:147](../../Sources/GraphiteUI/ReadAloudController.swift#L147)) skips both resume branches and calls `speakCurrentPassage` from `utteranceStartOffset = 0` ([ReadAloudSpeech.swift:557-569](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L557-L569)). The passage starts again from its first word.
- **Minimal fix:** Use `ReadAloudReanchoring.position(of: position, in: document)` and `session.move(to:offset:)`, as the edit path does ([ReadAloudController.swift:395-397](../../Sources/GraphiteUI/ReadAloudController.swift#L395-L397)).
- **Rule that prevents the class:** one owner per business rule (keeping the reading position after a re-preparation is implemented in one path and missing in the other)
- **Aliases:** none
- **Verifier notes:** The method's comment promises reading "goes on from where it was" ([ReadAloudController.swift:121-123](../../Sources/GraphiteUI/ReadAloudController.swift#L121-L123)). When reading was paused, the word is lost too: the next Play starts the passage over.

#### BUG-VOICE-10 Editing any pronunciation in Settings strips hand-written IPA from the vault's pronunciation file
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given; "Traced")
- **Reach:** iPad, iPhone and Mac. Only vaults whose file was edited by hand in the object form. Rare, but the loss is silent and permanent.
- **Trigger:** `.graphite/pronunciations.json` contains `"SIMDRAM": {"say": "sim dee ram", "ipa": "ˈsɪmdiːɹæm"}`, the form the type documents ([ReadAloudPronunciations.swift:52-54](../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L52-L54)). The user adds, edits or deletes any term in Settings › Read Aloud › Pronunciations.
- **Path:**
  1. `load` keeps only `(term, say)` ([ReadAloudPronunciationEditor.swift:95-98](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L95-L98)). `vaultEntries` had parsed the `ipa` ([ReadAloudPronunciations.swift:71-73](../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L71-L73)).
  2. Any change calls `save` with the whole list ([ReadAloudPronunciationEditor.swift:36-39](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L36-L39), [ReadAloudPronunciationEditor.swift:60-63](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L60-L63)). `vaultFileData` writes a `[String: String]` ([ReadAloudPronunciations.swift:80-88](../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L80-L88)).
  3. The file is replaced atomically ([ReadAloudPronunciationEditor.swift:104-106](../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L104-L106)). Every `ipa` field is gone.
- **Minimal fix:** Keep the full `Pronunciation` in the editor's entries and write the object form whenever `ipa` is present. Better still, rewrite only the changed key in the parsed JSON and keep all other content as found.
- **Rule that prevents the class:** persisted types have one validating construction path, golden tests, explicit encoding and a version (the file is read as one shape and written as another)
- **Aliases:** none
- **Verifier notes:** Other user content is dropped silently too: entries that `vaultEntries` skips (a term over 64 characters, a `say` over 200, entries past the first 2,000, values of other shapes; [ReadAloudPronunciations.swift:66-74](../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L66-L74)) are not written back. No test covers `vaultFileData` or `vaultEntries` (grep found none). A worse case of the same editor is BUG-VOICE-V01.

### PLUGIN

#### BUG-PLUGIN-01 Turning community plugins off and on again quickly leaves them off while the switch shows on
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal settings path. It needs a second toggle within the stop window, which lasts up to 2 s.
- **Trigger:** Settings › Community Plugins: turn "Turn On Community Plugins" off, then on before the stop has finished.
- **Path:** the toggle calls `setTurnedOnForVault(false)` in a new task ([CommunityPluginSettings.swift:21](../../Sources/GraphiteUI/CommunityPluginSettings.swift#L21)) → it stores false and awaits `stopRuntime()` ([CommunityPluginHost.swift:293-297](../../Sources/GraphiteUI/CommunityPluginHost.swift#L293-L297)) → `stopRuntime` passes its guard and suspends on `runtime.stop` or the 2 s timer while `isRuntimeRunning` is still true ([CommunityPluginHost.swift:507-514](../../Sources/GraphiteUI/CommunityPluginHost.swift#L507-L514)) → the second toggle stores true and calls `startIfNeeded` ([CommunityPluginHost.swift:295-297](../../Sources/GraphiteUI/CommunityPluginHost.swift#L295-L297)) → its guard requires `!isRuntimeRunning` and returns ([CommunityPluginHost.swift:353](../../Sources/GraphiteUI/CommunityPluginHost.swift#L353)) → the stop resumes and sets `isRuntimeRunning = false` ([CommunityPluginHost.swift:556](../../Sources/GraphiteUI/CommunityPluginHost.swift#L556)) → nothing starts. The enabled plugins read "Starts when community plugins run." ([CommunityPluginSettings.swift:154](../../Sources/GraphiteUI/CommunityPluginSettings.swift#L154)).
- **Minimal fix:** model the runtime as `stopped / starting / running / stopping`. A start requested while stopping is recorded and run when the stop ends.
- **Rule that prevents the class:** flows as enums, not booleans
- **Aliases:** none
- **Verifier notes:** the same dropped start affects `setEnabled` ([CommunityPluginHost.swift:610](../../Sources/GraphiteUI/CommunityPluginHost.swift#L610)), `openPluginLink` ([CommunityPluginHost.swift:1074-1075](../../Sources/GraphiteUI/CommunityPluginHost.swift#L1074-L1075)) and `runtimeProcessDidEnd`'s restart when another stop is in flight. "Reload Plugins" or reopening the vault recovers.

#### BUG-PLUGIN-02 A plugin whose `onload` never settles stops every later plugin from loading, and saved plugin views are never restored
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal start path, but only with a misbehaving or network-blocked plugin. Disabling that plugin and reloading recovers.
- **Trigger:** an enabled plugin's `onload` returns a promise that never settles.
- **Path:** `startIfNeeded` awaits each plugin in turn ([CommunityPluginHost.swift:411-414](../../Sources/GraphiteUI/CommunityPluginHost.swift#L411-L414)) → `load` uses `send` without a timeout ([CommunityPluginHost.swift:575-581](../../Sources/GraphiteUI/CommunityPluginHost.swift#L575-L581)), which awaits `callAsyncJavaScript` ([CommunityPluginHost.swift:840-842](../../Sources/GraphiteUI/CommunityPluginHost.swift#L840-L842)) → `receive` awaits the handler ([community-plugin-runtime-plugins.js:1541-1545](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1541-L1545)) → `loadPlugin` awaits `plugin.load()` ([community-plugin-runtime-plugins.js:624](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L624)) → which awaits `onload()` ([community-plugin-runtime-plugins.js:382-386](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L382-L386)) → `plugins.layoutReady`, `restorePluginViews` and `activeDocumentDidChange` are never reached ([CommunityPluginHost.swift:415-419](../../Sources/GraphiteUI/CommunityPluginHost.swift#L415-L419)). The hanging plugin shows "Starting…" ([CommunityPluginSettings.swift:155](../../Sources/GraphiteUI/CommunityPluginSettings.swift#L155)).
- **Minimal fix:** send `plugin.load` with `send(_:timeout:)` ([CommunityPluginHost.swift:822-836](../../Sources/GraphiteUI/CommunityPluginHost.swift#L822-L836)), mark a timed-out plugin as failed, and continue with the next plugin.
- **Rule that prevents the class:** *New rule:* every await on third-party code has a deadline, and its expiry is a reported outcome.
- **Aliases:** none
- **Verifier notes:** stopping still works, because `stopRuntime` has its own 2 s cap ([CommunityPluginHost.swift:510-514](../../Sources/GraphiteUI/CommunityPluginHost.swift#L510-L514)). The report's claim that Obsidian isolates such a plugin cannot be checked from the snapshot. The verdict rests on Graphite's own outcome: later plugins never load, and layout-ready callbacks of earlier plugins never run ([community-plugin-runtime-workspace.js:832-834](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L832-L834)).

#### BUG-PLUGIN-03 A plugin's `fileManager.renameFile` onto an existing name is answered as a success although nothing moved
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal plugin path when a plugin renames onto a taken name. Uncommon.
- **Trigger:** `app.fileManager.renameFile(file, newPath)` where `newPath` is an existing file.
- **Path:** the runtime sends `workspace.renameFile` ([community-plugin-runtime-vault.js:662-666](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L662-L666)) → the host calls `workspace.move` ([CommunityPluginHost.swift:925](../../Sources/GraphiteUI/CommunityPluginHost.swift#L925)) → `move` finds the destination taken, sets `errorMessage` and returns ([WorkspaceFileManagement.swift:92-95](../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L92-L95)) → no move is pending, so the wait loop ends at once ([CommunityPluginHost.swift:928-930](../../Sources/GraphiteUI/CommunityPluginHost.swift#L928-L930)) → `hasMoved()` checks only that a file exists at the destination ([CommunityPluginHost.swift:922-924](../../Sources/GraphiteUI/CommunityPluginHost.swift#L922-L924)), so the answer is `["stat": NSNull()]` ([CommunityPluginHost.swift:933](../../Sources/GraphiteUI/CommunityPluginHost.swift#L933)) → the runtime moves its revision record and its file-tree entry as if the rename had happened ([community-plugin-runtime-vault.js:667-668](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L667-L668)).
- **Minimal fix:** make `move(_:to:)` return an outcome (`moved`, `refused(reason)`, `awaitingAnswer`, `queued`) and answer the plugin from that outcome, not from a disk probe.
- **Rule that prevents the class:** outcomes as return values
- **Aliases:** none
- **Verifier notes:** other early returns in `move` behave the same way, including `pathsBeingMoved` ([WorkspaceFileManagement.swift:85](../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L85)): when the destination exists, the plugin gets a success; when it does not, the plugin waits 10 s and gets `cancelled`. No user data is lost. The plugin's later revision-checked write to the other note is refused as a conflict.

#### BUG-PLUGIN-04 A plugin's Bases view keeps stale formula values when results change but rows do not
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal path for bases shown through a plugin view type (TaskNotes, Kanban) that have formula columns.
- **Trigger:** a note edit changes a formula's value without changing which rows match, their order or their groups.
- **Path:** `CommunityPluginBasesViewContent` sends an update only when `resultSignature` changes ([CommunityPluginViews.swift:523-525](../../Sources/GraphiteUI/CommunityPluginViews.swift#L523-L525)) → the signature is the group keys' text plus the row paths ([CommunityPluginViews.swift:505](../../Sources/GraphiteUI/CommunityPluginViews.swift#L505)) → formula values exist only in the message `basesMessage` builds ([CommunityPluginViews.swift:142-156](../../Sources/GraphiteUI/CommunityPluginViews.swift#L142-L156)) → the runtime's `BasesEntry` answers formulas from the values it last received ([community-plugin-runtime-bases.js:195-200](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L195-L200), [community-plugin-runtime-bases.js:295-296](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L295-L296)).
- **Minimal fix:** compare the whole message `basesMessage(result)` (or a hash of it) instead of the row signature, so formula values and `properties` changes are sent too.
- **Rule that prevents the class:** derived state as projections (the change key is the projection of everything sent)
- **Aliases:** none
- **Verifier notes:** a change of the view's columns alone is not sent either, because `properties` is not in the signature ([CommunityPluginViews.swift:156](../../Sources/GraphiteUI/CommunityPluginViews.swift#L156)). Note properties stay current because the runtime reads them from its metadata cache ([community-plugin-runtime-bases.js:219-222](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-bases.js#L219-L222)).

#### BUG-PLUGIN-05 A failed keychain read makes the next plugin secret save erase the vault's other secrets
- **Verdict:** Plausible
- **Severity:** Medium  (reported: none given)
- **Reach:** mainly Mac builds that use the login keychain ([CommunityPluginSecretStore.swift:17-30](../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L17-L30)). On iPad and iPhone the item is readable after first unlock, which always holds while the app is in use. Rare.
- **Trigger:** a plugin calls `app.secretStorage.setSecret` while `SecItemCopyMatching` fails, or while the stored data does not decode as `[String: String]`.
- **Path:** the host receives `secrets.set` and calls `setSecret` ([CommunityPluginHost.swift:1046-1049](../../Sources/GraphiteUI/CommunityPluginHost.swift#L1046-L1049)) → `setSecret` starts from `secrets()` ([CommunityPluginSecretStore.swift:53](../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L53)), which answers `[:]` for any non-success status and for undecodable data ([CommunityPluginSecretStore.swift:47-49](../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L47-L49)) → `SecItemUpdate` replaces the item with only the new secret ([CommunityPluginSecretStore.swift:58](../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L58)).
- **Minimal fix:** `secrets()` throws on any status other than success or `errSecItemNotFound`, and on undecodable data. `setSecret` then refuses to write.
- **Rule that prevents the class:** failed reads are never empty results
- **Aliases:** none
- **Verifier notes:** the code path is certain. Whether a read can fail while the following update succeeds is not. One case would settle it: on the Mac login keychain, deny the access prompt for the read (`errSecAuthFailed`) and allow the one for the update, for example after a re-signed build. Undecodable data needs another writer of the same service and account, and nothing in the snapshot writes one.

#### BUG-PLUGIN-06 Leaving a vault, reloading plugins or turning them off erases the vault's saved plugin views
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal path for every plugin that registers a view, on every vault switch, Reload Plugins or turn-off. The person can reopen the views by hand.
- **Trigger:** a plugin view is open in a tab or the sidebar, and the person switches vault, presses "Reload Plugins" or turns plugins off.
- **Path:** `openVault` calls `vaultWillClose()` while `layoutVaultIdentifier` still names the old vault ([WorkspaceModel.swift:299](../../Sources/GraphiteUI/WorkspaceModel.swift#L299), [WorkspaceModel.swift:311](../../Sources/GraphiteUI/WorkspaceModel.swift#L311)). `restartPlugins` and turn-off call `stopRuntime` directly ([CommunityPluginHost.swift:620-627](../../Sources/GraphiteUI/CommunityPluginHost.swift#L620-L627), [CommunityPluginHost.swift:297](../../Sources/GraphiteUI/CommunityPluginHost.swift#L297)) → `stopRuntime` awaits `runtime.stop`, with the message handler still installed ([CommunityPluginHost.swift:510-515](../../Sources/GraphiteUI/CommunityPluginHost.swift#L510-L515)) → the page unloads each plugin ([community-plugin-runtime-plugins.js:1272](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1272)) → `unload` runs the cleanup that `registerView` registered ([community-plugin-runtime-foundation.js:167-175](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L167-L175), [community-plugin-runtime-plugins.js:457-460](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L457-L460)) → each `detach` posts `views.changed` ([community-plugin-runtime-workspace.js:678-687](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L678-L687), [community-plugin-runtime-workspace.js:816](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L816)) → the main actor is free, so the receiver answers it ([CommunityPluginWebContent.swift:116-119](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L116-L119)) → the host takes the shorter list and calls `pluginViewsDidChange()` ([CommunityPluginHost.swift:949-956](../../Sources/GraphiteUI/CommunityPluginHost.swift#L949-L956)) → tabs whose view is gone lose `restorablePluginView`, the sidebar list becomes empty because `hasRestoredViews` is still true, and the layout is saved ([CommunityPluginViews.swift:227-244](../../Sources/GraphiteUI/CommunityPluginViews.swift#L227-L244)) → an empty sidebar list leaves `sidebarPluginViews` unset in the saved layout ([CommunityPluginViews.swift:263-266](../../Sources/GraphiteUI/CommunityPluginViews.swift#L263-L266), [TabLayout.swift:326-330](../../Sources/GraphiteCore/TabLayout.swift#L326-L330)) → it is written under the vault being left ([WorkspaceTabs.swift:419-421](../../Sources/GraphiteUI/WorkspaceTabs.swift#L419-L421)).
- **Minimal fix:** before sending `runtime.stop`, set `hasRestoredViews = false` and mark the host as stopping. `pluginViewsDidChange` then ignores view removals while stopping, as it already does before views are restored.
- **Rule that prevents the class:** flows as enums, not booleans (a `stopping` phase separates teardown from the person closing a view)
- **Aliases:** none
- **Verifier notes:** no test covers layout persistence across a stop. `Tests/**` has no `restorePluginViews` test, and the hosted test only checks that a closed view leaves its tab ([CommunityPluginHostTests.swift:314-335](../../App/Tests/CommunityPluginHostTests.swift#L314-L335)). Quitting the app keeps the views, because nothing stops the runtime then. That explains why restoring appears to work.

### RUNTIME

#### BUG-RUNTIME-01 A plugin's asynchronous edit lands in the note the person switched to
- **Verdict:** Confirmed
- **Severity:** High  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal path for any editor command that awaits before editing (Templater, QuickAdd, AI plugins), when the person changes note while it waits.
- **Trigger:** a command's `editorCallback` on note A awaits something and then calls `replaceRange` or `replaceSelection` on its `editor`. While it waits, the person selects note B.
- **Path:** `run` sends `command.run` with A's snapshot ([CommunityPluginHost.swift:660](../../Sources/GraphiteUI/CommunityPluginHost.swift#L660)) → `setActiveDocument` puts it into the mirror leaf's one editor ([community-plugin-runtime-plugins.js:1376](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1376), [community-plugin-runtime-workspace.js:767](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L767), [community-plugin-runtime-workspace.js:782-788](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L782-L788)) → `executeCommand` hands that object to the plugin ([community-plugin-runtime-plugins.js:213-222](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L213-L222)) → the selection change triggers `activeDocumentDidChange` ([CommunityPluginPresentation.swift:236](../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L236), [CommunityPluginHost.swift:716-719](../../Sources/GraphiteUI/CommunityPluginHost.swift#L716-L719)) → `setActiveDocument` keeps the same `MarkdownView` ([community-plugin-runtime-workspace.js:762-764](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L762-L764)) and calls `adoptSnapshot` on the same editor ([community-plugin-runtime-workspace.js:785](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L785)), which now holds B's path, identifier and text ([community-plugin-runtime-workspace.js:163-174](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L163-L174)) → the plugin's edit is clamped to B's lines ([community-plugin-runtime-workspace.js:194-199](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L194-L199), [community-plugin-runtime-workspace.js:266-277](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L266-L277)) and flushed with B's path and identifier ([community-plugin-runtime-workspace.js:383-390](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L383-L390)) → the host finds B's snapshot equal to B's text and applies the edit ([CommunityPluginHost.swift:768-788](../../Sources/GraphiteUI/CommunityPluginHost.swift#L768-L788)).
- **Minimal fix:** give each `command.run` (and each newly focused note) its own `SnapshotEditor` object instead of re-pointing the shared one. An editor keeps its note's path and identifier for life, so a late edit is checked against A and refused or applied there.
- **Rule that prevents the class:** identity equals equality (an editor object stands for one note snapshot)
- **Aliases:** none
- **Verifier notes:** the host's guard does not help, because `adoptSnapshot` also replaces the snapshot identifier that the guard checks. `replaceRange` with a range deletes text in B. The edit is one undoable change, which is why I rate it High rather than Critical. The Node tests switch notes only between commands ([editor-commands.test.js:135-155](../../Tests/CommunityPluginRuntimeTests/tests/editor-commands.test.js#L135-L155)) and do not pin the opposite behaviour.

#### BUG-RUNTIME-02 Keyboard shortcuts plugins register with `Mod` never fire
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given)
- **Reach:** Mac, and iPad and iPhone with a hardware keyboard. Normal path for plugin modals and suggesters that bind `Mod+Enter` and similar keys. Tapping the same control still works.
- **Trigger:** `this.scope.register(['Mod'], 'Enter', submit)` in a modal, and the person presses Command-Return.
- **Path:** `register` stores the modifiers as given, sorted and joined: `'Mod'` ([community-plugin-runtime-interface.js:126-130](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L126-L130)) → the modal's capture listener calls `scope.handleKeyEvent` ([community-plugin-runtime-interface.js:364](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L364)) → `modifiersOf` yields only `Alt`, `Ctrl`, `Meta`, `Shift`, here `'Meta'` ([community-plugin-runtime-interface.js:163-170](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L163-L170)) → `'Mod' !== 'Meta'`, so no handler matches and the parent scope answers false ([community-plugin-runtime-interface.js:134-147](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L134-L147)).
- **Minimal fix:** in `register`, map `Mod` to `Meta` (Apple platforms) before sorting, the mapping `Keymap.isModifier` already applies ([community-plugin-runtime-interface.js:171-174](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-interface.js#L171-L174)).
- **Rule that prevents the class:** one owner per business rule (what `Mod` means)
- **Aliases:** none
- **Verifier notes:** a grep of `Tests/CommunityPluginRuntimeTests/**` for `scope.register` and `'Mod'` finds nothing, so no test covers `Scope`. Combinations such as `['Mod','Shift']` fail the same way.

#### BUG-RUNTIME-03 A plugin view opened "in the current tab" never appears and is never closed
- **Verdict:** Confirmed
- **Severity:** Medium  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Normal path for plugins that open their view with `getLeaf(false)`, `getLeaf()`, `getUnpinnedLeaf()` or `getMostRecentLeaf()` while a note is focused.
- **Trigger:** `app.workspace.getLeaf(false).setViewState({ type: MY_VIEW, active: true })` with a note focused.
- **Path:** a focused note makes the mirror leaf active ([community-plugin-runtime-workspace.js:769](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L769)) → `getLeaf(false)` returns `markdownLeaf` ([community-plugin-runtime-workspace.js:847-851](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L847-L851)) → `setViewState` builds the view and opens it in the leaf's `containerEl` ([community-plugin-runtime-workspace.js:609-620](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L609-L620), [community-plugin-runtime-workspace.js:626-633](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L626-L633)). That element is never placed, because only `createPluginLeaf` calls `placeNewLeaf` ([community-plugin-runtime-workspace.js:717](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L717), [community-plugin-runtime-workspace.js:868-872](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L868-L872)) → `revealLeaf` returns for the mirror leaf ([community-plugin-runtime-workspace.js:900-901](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L900-L901)), `views.changed` lists `pluginLeaves` only ([community-plugin-runtime-workspace.js:818](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L818)), and `showIfNew` returns for kind `mirror` ([community-plugin-runtime-workspace.js:649](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L649)) → the next focus message replaces the view with a new `MarkdownView` or `EmptyView` without closing it ([community-plugin-runtime-workspace.js:762](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L762), [community-plugin-runtime-workspace.js:772](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L772)).
- **Minimal fix:** `setViewState` on the mirror leaf, for any type other than `markdown`, opens the view in a new plugin leaf (`createPluginLeaf('tab')`) and leaves the mirror untouched. Or `getLeaf(false)` returns a new tab leaf when the active leaf is the mirror.
- **Rule that prevents the class:** one owner per business rule (where a plugin view is placed is decided by `createPluginLeaf` only)
- **Aliases:** none
- **Verifier notes:** until the next focus message, `getActiveViewOfType(MarkdownView)` answers null ([community-plugin-runtime-workspace.js:839-842](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L839-L842)), so editor commands report unavailable. The orphaned view's registered intervals and events run until its plugin unloads.

#### BUG-RUNTIME-04 A theme's `-theme` font variables do not reach plugin pages or block copies
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Themes that set fonts through `--font-text-theme` / `--font-interface-theme`. The effect is cosmetic.
- **Trigger:** such a theme is active and a plugin draws a block or a view.
- **Path:** the default layer derives `--font-text` and `--font-interface` from the `-theme` variables at `:where(body)` ([graphite-default-variables.css:15-23](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L15-L23)) → the runtime page and the copy page load `community-plugin-runtime.css` after that layer ([index.html:9-10](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/index.html#L9-L10), [CommunityPluginReadingBlocks.swift:409-410](../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L409-L410)) → that file sets `--font-interface`, `--font-text` and `--font-monospace` to literal system fonts in a selector of the same zero specificity, later in source order, so it wins ([community-plugin-runtime.css:11-14](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L11-L14)) → rendered Markdown uses `var(--font-text)` ([community-plugin-runtime.css:184](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L184)). The theme probe measures against the default layer alone ([ThemeTokenResolver.swift:129](../../Sources/GraphiteUI/ThemeTokenResolver.swift#L129), [ThemeTokenResolver.swift:142](../../Sources/GraphiteUI/ThemeTokenResolver.swift#L142)), so native notes do follow the theme.
- **Minimal fix:** delete the three font lines from `community-plugin-runtime.css`. The default layer already gives the same system fonts when no theme sets them.
- **Rule that prevents the class:** one owner per business rule (each CSS variable is defined in one layer)
- **Aliases:** none
- **Verifier notes:** CSS cascade order is deterministic, so no runtime check is needed. A theme that overrides `--font-text` itself in `body { … }` still wins, because a type selector has more specificity than `:where`.

#### BUG-RUNTIME-05 An image-map link in a rendered note navigates the plugins' page away
- **Verdict:** Refuted
- **Severity:** Low  (reported: none given)
- **Reach:** iPad, iPhone, Mac. Raw HTML image maps in notes rendered for plugins are rare.
- **Trigger (as reported):** `<area href="https://example.com">` in a section a plugin post-processes, tapped in the copy.
- **Path:** the sanitizer keeps `area` and its `href` ([community-plugin-runtime-foundation.js:494-509](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L494-L509), [community-plugin-runtime-reading.js:498-500](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L498-L500)) → the tap is replayed as `element.click()` ([community-plugin-runtime-reading.js:719](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L719), [community-plugin-runtime-reading.js:534](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L534)) → the page's guard handles only `closest('a')` ([community-plugin-runtime-reading.js:747-748](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L747-L748)), so the area's navigation starts → the web view's navigation delegate answers `.cancel` for every `http`, `https` and `mailto` address, and opens it in the browser when it is a link activation ([CommunityPluginWebContent.swift:148-151](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L148-L151)). Addresses on the plugin scheme other than the runtime page are cancelled too ([CommunityPluginWebContent.swift:141-146](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L141-L146)). The runtime page stays.
- **Minimal fix:** none for the reported trigger. For hygiene, extend `followLink` to `closest('a, area')`, so the area link opens through Graphite like an anchor.
- **Rule that prevents the class:** bounded parsing of untrusted input (allow-list sanitizing and navigation)
- **Aliases:** none
- **Verifier notes:** the report did not read the navigation delegate. The one address family the delegate allows on the main frame is `about:` ([CommunityPluginWebContent.swift:147](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L147)), which is filed separately as BUG-RUNTIME-V01. Note that the guard's comment ([community-plugin-runtime-reading.js:741-743](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L741-L743)) overstates the risk for web links, because the delegate already stops them.

#### BUG-RUNTIME-06 A note's cached metadata can end older than its file
- **Verdict:** Plausible
- **Severity:** Low  (reported: none given)
- **Reach:** iPad, iPhone, Mac. It needs answers to arrive out of order. That is rare in practice.
- **Trigger:** two reads of one note are in flight, or a queued read is in flight while a plugin writes the same note.
- **Path:** each `modify` enqueues a read ([community-plugin-runtime-metadata.js:607-609](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L607-L609)) → up to four reads run at once with no per-path order ([community-plugin-runtime-metadata.js:562-572](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L562-L572)) → each read stores its result when its answer arrives. The only check compares file objects ([community-plugin-runtime-metadata.js:574-580](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L574-L580)) → a plugin's own write stores its text at once ([community-plugin-runtime-metadata.js:592-595](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L592-L595)), and an older read answered later overwrites it.
- **Minimal fix:** keep a per-path read generation. A read stores its result only if no later read or `indexWrittenText` for that path happened, or it compares the answer's `revision` with the newest known one.
- **Rule that prevents the class:** every task has an owner that cancels it, latest-answer-wins through one primitive
- **Aliases:** none
- **Verifier notes:** on the host side, reads enter the `VaultStore` actor ([VaultStore.swift:66](../../Sources/GraphiteCore/VaultStore.swift#L66), [VaultStore.swift:97](../../Sources/GraphiteCore/VaultStore.swift#L97)) through a nonisolated `respond` ([CommunityPluginVaultBridge.swift:34-42](../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L34-L42), [CommunityPluginVaultBridge.swift:184-206](../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L184-L206)). The store work is serialized, but each answer is encoded and returned after the store work. Two `modify` batches are at least 300 ms apart ([CommunityPluginHost.swift:804-810](../../Sources/GraphiteUI/CommunityPluginHost.swift#L804-L810)), so the read-read case is unlikely. The read-then-plugin-write case is more likely: a large note's read answer (JSON of the whole text) can arrive after a small write answer. A Node harness test can settle the JavaScript side by delaying the first `vault.read` answer. On a device, logging answer order under load would settle it.

#### BUG-RUNTIME-07 `app.getTheme()` answers dark on a light page
- **Verdict:** Confirmed
- **Severity:** Low  (reported: none given)
- **Reach:** iPad, iPhone, Mac in the light appearance, for vaults whose `appearance.json` has no `theme`, `"system"` or `"obsidian"`. Common, but only plugins that style by `getTheme()` show it.
- **Trigger:** a plugin calls `app.getTheme()` while Graphite is light.
- **Path:** the host sends `appearance.json` as is ([CommunityPluginThemes.swift:38-43](../../Sources/GraphiteUI/CommunityPluginThemes.swift#L38-L43), [CommunityPluginHost.swift:461](../../Sources/GraphiteUI/CommunityPluginHost.swift#L461)) → `getConfig('theme')` falls back to `'system'` ([community-plugin-runtime-vault.js:613-617](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L613-L617), [community-plugin-runtime-vault.js:82](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L82)) → `getTheme` answers `'moonstone'` only for exactly `'moonstone'`, otherwise `'obsidian'` ([community-plugin-runtime-plugins.js:922](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L922)) → the page carries `theme-light` ([community-plugin-runtime-plugins.js:1235-1240](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1235-L1240)) and `isDarkMode()` answers false ([community-plugin-runtime-plugins.js:919](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L919)).
- **Minimal fix:** `getTheme()` returns `this.isDarkMode() ? 'obsidian' : 'moonstone'`, as the `vault.config` getter already derives `theme` from the body class ([community-plugin-runtime-vault.js:609](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L609)).
- **Rule that prevents the class:** derived state as projections (the theme name is projected from the page's appearance)
- **Aliases:** none
- **Verifier notes:** the report's open question is settled: the host sends the raw file, so no host-side default supplies `theme`. Tests check only a value from the allowed set ([obsidian-conventions.test.js:79](../../Tests/CommunityPluginRuntimeTests/tests/obsidian-conventions.test.js#L79)) and the value after `setTheme('moonstone')` ([themes.test.js:97-101](../../Tests/CommunityPluginRuntimeTests/tests/themes.test.js#L97-L101)). Neither pins the dark answer on a light page. The runtime holds two different answers for "the theme": `config.theme` and `getConfig('theme')`.

#### BUG-RUNTIME-V01 An `about:` link in an image map replaces the runtime page and silently ends every plugin
- **Verdict:** Plausible
- **Severity:** Low
- **Reach:** iPad, iPhone, Mac. It needs raw HTML `<area href="about:blank">` in a note rendered for plugins, or a plugin navigating the page to `about:`. Very rare.
- **Trigger:** a note section holds `<map><area href="about:blank" …></map>` over an image, a plugin post-processes the section, and the person taps the area in the copy.
- **Path:** the sanitizer keeps `area` and any non-`javascript:` `href` ([community-plugin-runtime-foundation.js:494-509](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L494-L509)) → the tap is replayed as `element.click()` ([community-plugin-runtime-reading.js:534](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L534)) → `followLink` ignores non-anchors ([community-plugin-runtime-reading.js:747-748](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L747-L748)) → the delegate allows any `about:` address for any frame, main frame included ([CommunityPluginWebContent.swift:147](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L147)) → the runtime page is replaced. No content-process end is reported, so `isRuntimeRunning` stays true ([CommunityPluginWebContent.swift:134-136](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L134-L136)), and every later `send` goes to a page without `GraphitePluginRuntime` ([CommunityPluginHost.swift:842](../../Sources/GraphiteUI/CommunityPluginHost.swift#L842)).
- **Minimal fix:** allow `about:` only for subframes (`navigationAction.targetFrame?.isMainFrame == false`), as is already done for the plugin scheme ([CommunityPluginWebContent.swift:144](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L144)), and extend `followLink` to `area`.
- **Rule that prevents the class:** bounded parsing of untrusted input (allow-list sanitizing and navigation)
- **Aliases:** none (the reported trigger is refuted as BUG-RUNTIME-05)
- **Verifier notes:** the Graphite steps are read in full. Whether swift-markdown's `HTMLFormatter` passes the raw `<map>` block through ([CommunityPluginEditorChange.swift:50](../../Sources/GraphiteCore/CommunityPluginEditorChange.swift#L50)) cannot be read, because the library is not in the snapshot. A unit test that renders such a note through `CommunityPluginMarkdownRendering.html(for:)` settles it.

### ARCH

#### BUG-ARCH-01 Following a link to a missing `.flac`, `.ogg`, `.webm`, `.m4v` or `.3gp` file creates a note named `name.flac.md`
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Traced")
- **Reach:** iPad, iPhone, Mac. Normal link-following path, but only for links to missing media files with those five extensions, after the first scan. Rare.
- **Trigger:** The person taps `[[Lecture.flac]]` and no such file exists.
- **Path:**
  1. `follow` finds nothing through `resolveLink` ([WorkspaceModel.swift:676](../../Sources/GraphiteUI/WorkspaceModel.swift#L676)). The index has no match and the scan is complete, so it calls `createNote(forLink:)` ([WorkspaceModel.swift:697-702](../../Sources/GraphiteUI/WorkspaceModel.swift#L697-L702)).
  2. The extension is not `md`. `DocumentKind(fileExtension: "flac")` is `.other` because the switch lists only `m4a, mp4, mov, mp3, wav, aac` as media ([VaultPath.swift:161-170](../../Sources/GraphiteCore/VaultPath.swift#L161-L170)). The whole file name becomes the stem ([WorkspaceModel.swift:746-749](../../Sources/GraphiteUI/WorkspaceModel.swift#L746-L749)), and the attachment guard ([WorkspaceModel.swift:750-753](../../Sources/GraphiteUI/WorkspaceModel.swift#L750-L753)) is skipped.
  3. `Lecture.flac.md` is written and opened ([WorkspaceModel.swift:764-768](../../Sources/GraphiteUI/WorkspaceModel.swift#L764-L768)).
- **Minimal fix:** Make `DocumentKind` the single owner of media extensions (add `flac, ogg, 3gp, webm, m4v` to `.media`), and derive `MediaFileKind.audioExtensions`/`videoExtensions` ([MarkdownPreview.swift:233-234](../../Sources/GraphiteUI/MarkdownPreview.swift#L233-L234)) from it.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** The guard is pinned for `.png` only ([UiWorkspaceModelFixTests.swift:187-198](../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L187-L198)). Nothing tests media extensions; `flac`, `ogg` and `webm` do not occur in any test. The stray note is recoverable by deleting it, so I rate this Low.

#### BUG-ARCH-02 Quitting the Mac app discards unsaved edits when a save fails or takes longer than 5 seconds
- **Verdict:** Confirmed (duplicate)
- **Severity:** High (reported: none given; "Traced")
- **Reach:** Mac. See BUG-SHELL-03.
- **Trigger:** As in BUG-SHELL-03.
- **Path:** Same trace as BUG-SHELL-03: [GraphiteMacScenes.swift:54-61](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L54-L61) → [WorkspaceModel.swift:487-493](../../Sources/GraphiteUI/WorkspaceModel.swift#L487-L493) → [MarkdownSession.swift:153-154](../../Sources/GraphiteUI/MarkdownSession.swift#L153-L154) → termination allowed.
- **Minimal fix:** See BUG-SHELL-03.
- **Rule that prevents the class:** unreadable data moved aside, writes report failure
- **Aliases:** duplicate of BUG-SHELL-03 (kept under that ID)
- **Verifier notes:** Same defect. This entry's claim that File recovery does not cover unsaved text is correct ([WorkspaceRecovery.swift:16-24](../../Sources/GraphiteUI/WorkspaceRecovery.swift#L16-L24)).

#### BUG-ARCH-03 A drawing open in the editor during a vault switch is saved into the newly opened vault
- **Verdict:** Plausible
- **Severity:** Low (reported: none given; "Partly traced")
- **Reach:** iPad and iPhone (the drawing editor is UIKit-only). Uncommon: it needs a `graphite://` link that switches vaults (`open?vault=` or `open?path=` into another known vault) while the full-screen drawing editor is up. The drawing is not lost; it lands in the wrong vault.
- **Trigger:** The person is drawing a new drawing for a note in vault A. A Shortcut or another app opens `graphite://open?vault=B`. The person taps Insert.
- **Path:**
  1. If SwiftUI delivers the URL, `.onOpenURL` calls `handle` ([GraphiteRootView.swift:224-226](../../Sources/GraphiteUI/GraphiteRootView.swift#L224-L226)), which switches vault ([WorkspaceDeepLinks.swift:15-24](../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L15-L24)).
  2. `prepareToLeaveCurrentVault` refuses only during a recording ([WorkspaceModel.swift:261-265](../../Sources/GraphiteUI/WorkspaceModel.swift#L261-L265)). The reset in `openVault` does not touch `drawingEditorRequest` ([WorkspaceModel.swift:303-323](../../Sources/GraphiteUI/WorkspaceModel.swift#L303-L323)), so the cover stays up ([GraphiteRootView.swift:177-191](../../Sources/GraphiteUI/GraphiteRootView.swift#L177-L191)). The draft reopener does nothing while a request is open ([GraphiteRootView.swift:572](../../Sources/GraphiteUI/GraphiteRootView.swift#L572)).
  3. Insert calls `saveDrawing` with the old request ([GraphiteRootView.swift:178-179](../../Sources/GraphiteUI/GraphiteRootView.swift#L178-L179)). `saveDrawing` reads the current `store` and `folderAccess` ([WorkspaceModel.swift:1042](../../Sources/GraphiteUI/WorkspaceModel.swift#L1042)) and the current vault's settings, creates the attachment folder from the old note's relative path, and writes there ([WorkspaceModel.swift:1046-1050](../../Sources/GraphiteUI/WorkspaceModel.swift#L1046-L1050)).
  4. The note is not open in B, so the message says the drawing was saved but no embed was inserted ([WorkspaceModel.swift:1064-1066](../../Sources/GraphiteUI/WorkspaceModel.swift#L1064-L1066)). A draft preserved meanwhile is tagged with B's identifier ([GraphiteRootView.swift:183-185](../../Sources/GraphiteUI/GraphiteRootView.swift#L183-L185)).
- **Minimal fix:** Capture the vault's identifier and `FolderAccess` in `DrawingEditorRequest` when it is made, and save through those, as recording does with `recordingFolderAccess` ([WorkspaceModel.swift:1098-1101](../../Sources/GraphiteUI/WorkspaceModel.swift#L1098-L1101)). Or refuse a vault switch while `drawingEditorRequest != nil`.
- **Rule that prevents the class:** *New rule:* vault-scoped state and the work started in a vault live in one per-vault container that is replaced (or drained) on a switch, and nothing reads "the current vault" after an await.
- **Aliases:** none
- **Verifier notes:** Every Graphite step is traced. What decides the verdict is whether `onOpenURL` on the root view fires while a `fullScreenCover` is presented. A UI test settles it: present the drawing editor, open `graphite://open?vault=<other>` with `XCUIApplication.open(_:)`, and check whether `currentVaultIdentifier` changes. The other switch trigger, `vaultFolderDidMove`, reopens the same vault ([WorkspaceModel.swift:352-367](../../Sources/GraphiteUI/WorkspaceModel.swift#L352-L367)), so the drawing still goes to the right vault on that path.

#### BUG-ARCH-04 Text typed while a vault switch unloads plugins is dropped when its save fails
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Traced")
- **Reach:** iPad, iPhone, Mac. Very narrow: text must be typed during the awaits after the checked save, and that save must then fail. Any conflict that existed earlier already stops the switch at [WorkspaceModel.swift:264](../../Sources/GraphiteUI/WorkspaceModel.swift#L264) or [291](../../Sources/GraphiteUI/WorkspaceModel.swift#L291).
- **Trigger:** During `saveVaultAppearanceNow()` or `communityPlugins.vaultWillClose()`, the person keeps typing, and the note changes on disk (or the write is refused) before the final save.
- **Path:**
  1. The checked save keeps the vault open on failure ([WorkspaceModel.swift:289-297](../../Sources/GraphiteUI/WorkspaceModel.swift#L289-L297)).
  2. Then come `await communityPlugins.vaultWillClose()` ([WorkspaceModel.swift:299](../../Sources/GraphiteUI/WorkspaceModel.swift#L299)) and `try? await document.saveAllChanges()` ([WorkspaceModel.swift:302](../../Sources/GraphiteUI/WorkspaceModel.swift#L302)). `saveAllChanges` exits on the first throw ([WorkspaceTabs.swift:52-54](../../Sources/GraphiteUI/WorkspaceTabs.swift#L52-L54)), and `try?` drops the error.
  3. `tabDocuments = [:]` releases the sessions with their text ([WorkspaceModel.swift:312](../../Sources/GraphiteUI/WorkspaceModel.swift#L312)).
- **Minimal fix:** When this save fails, write each failing session's text with `saveSeparateCopy`, or abort the switch with the error as at line 291, before releasing the documents.
- **Rule that prevents the class:** unreadable data moved aside, writes report failure
- **Aliases:** none
- **Verifier notes:** The success case is tested ([UiWorkspaceModelFixTests.swift:134-149](../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L134-L149)); the failure case is not. Same class as SHELL-03, but much rarer.

#### BUG-ARCH-05 With a theme, a link to a missing note named like a folder is drawn as resolved, and its embed resolves to the folder
- **Verdict:** Confirmed
- **Severity:** Low (reported: none given; "Traced"/"Partly traced")
- **Reach:** iPad, iPhone, Mac. Reading view. The marking error needs a theme. The embed error happens with or without one, whenever a folder has the name of a missing note beside the note or at the root.
- **Trigger:** `[[Projects]]` or `![[Projects]]`, with no `Projects.md` and a folder `Projects`.
- **Path:**
  1. The reading view's `resolve` returns the first direct candidate that exists, folders included ([MarkdownPreview.swift:488-491](../../Sources/GraphiteUI/MarkdownPreview.swift#L488-L491)). The candidates include the bare name ([MarkdownSemantics.swift:873-875](../../Sources/GraphiteCore/MarkdownSemantics.swift#L873-L875), [898-901](../../Sources/GraphiteCore/MarkdownSemantics.swift#L898-L901)).
  2. Marking: the link counts as unresolved only when `resolve` returns nil ([MarkdownPreview.swift:556-559](../../Sources/GraphiteUI/MarkdownPreview.swift#L556-L559)). Here it returns the folder, so the link is drawn as resolved.
  3. Embed: `renderEmbed` gets the folder ([MarkdownPreview.swift:442-445](../../Sources/GraphiteUI/MarkdownPreview.swift#L442-L445)). Its kind is `.other`, so it falls to `default` ([MarkdownPreview.swift:476-478](../../Sources/GraphiteUI/MarkdownPreview.swift#L476-L478)). `prepared` turns it into a link labelled "Projects" to the folder path ([MarkdownPreview.swift:535-549](../../Sources/GraphiteUI/MarkdownPreview.swift#L535-L549)) instead of the missing-embed notice ([MarkdownPreview.swift:444](../../Sources/GraphiteUI/MarkdownPreview.swift#L444)).
  4. Tapping goes to `WorkspaceModel.resolveLink`, which skips folders ([WorkspaceModel.swift:656-659](../../Sources/GraphiteUI/WorkspaceModel.swift#L656-L659)), and `follow` creates `Projects.md` ([WorkspaceModel.swift:699-702](../../Sources/GraphiteUI/WorkspaceModel.swift#L699-L702)).
- **Minimal fix:** Use one resolver for both. Move the "regular files only" check into a Core function (`VaultStore.regularFileExists` already exists, [VaultStore.swift:110-113](../../Sources/GraphiteCore/VaultStore.swift#L110-L113)) and call it from `MarkdownPreview.resolve` and `WorkspaceModel.resolveLink`.
- **Rule that prevents the class:** one owner per business rule
- **Aliases:** none
- **Verifier notes:** I closed the embed half the report left partly traced: a folder embed is drawn as a plain link to the folder. The workspace side is pinned by [UiWorkspaceModelFixTests.swift:200-214](../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L200-L214); nothing pins the reading view.

#### BUG-ARCH-06 Removing a vault leaves its folds in the device's preferences
- **Verdict:** Confirmed (duplicate)
- **Severity:** Low (reported: none given; "Traced")
- **Reach:** See BUG-SHELL-02.
- **Trigger:** Removing a vault from the vault list.
- **Path:** [WorkspaceModel.swift:254-257](../../Sources/GraphiteUI/WorkspaceModel.swift#L254-L257) leaves `GraphiteFolds.<uuid>` ([WorkspaceFolds.swift:7-9](../../Sources/GraphiteUI/WorkspaceFolds.swift#L7-L9)).
- **Minimal fix:** See BUG-SHELL-02.
- **Rule that prevents the class:** one owner per persisted key
- **Aliases:** duplicate of BUG-SHELL-02 (kept under that ID)
- **Verifier notes:** Same defect.

#### BUG-ARCH-07 Read Aloud resumes a note at a place remembered for a same-named note of another vault
- **Verdict:** Confirmed
- **Severity:** Medium (reported: none given; "Partly traced")
- **Reach:** All platforms. Normal path for anyone with several vaults that share note paths (daily notes such as `2024-05-01.md`, `README.md`, `Index.md`). The reach is wider than reported: the ordinary "Read aloud" on a note resumes the same way, not only the queue.
- **Trigger:** The person listens to `Lecture.md` in vault A, opens vault B, and reads B's `Lecture.md` aloud, from the note's menu or from the queue.
- **Path:**
  1. `readMarkdown` starts with `sourceIdentifier: path.rawValue`, the vault-relative path ([ReadAloudController.swift:97-100](../../Sources/GraphiteUI/ReadAloudController.swift#L97-L100), [591-598](../../Sources/GraphiteUI/ReadAloudController.swift#L591-L598)).
  2. `readingChanged` saves positions under that identifier ([ReadAloudNavigator.swift:387-395](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L387-L395)), in one app-wide dictionary ([ReadAloudNavigator.swift:53](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L53), [357-370](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L357-L370)).
  3. In vault B, `MarkdownPane.startReading` resumes at `rememberedLocation(for: session.path.rawValue)` ([MarkdownPane.swift:564-571](../../Sources/GraphiteUI/MarkdownPane.swift#L564-L571)). The queue path does the same ([ReadAloudNavigator.swift:304-317](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L304-L317), [330-331](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L330-L331); [WorkspaceModel.swift:1457-1463](../../Sources/GraphiteUI/WorkspaceModel.swift#L1457-L1463)).
  4. Outcome: reading starts mid-note, at A's offset.
- **Minimal fix:** Key positions by vault identifier plus path (`"<uuid>|<path>"`), or move them into a per-vault key removed by `removeFromVaultList`.
- **Rule that prevents the class:** one owner per persisted key
- **Aliases:** none
- **Verifier notes:** I read the `sourceIdentifier` assignment the report did not read. The report missed the main trigger, `MarkdownPane.startReading`; that is why I rate this Medium rather than Low. The player offers Start Over, so the person can recover.

#### BUG-ARCH-V01 The listening queue and its history carry into the next vault and read old-vault paths there
- **Verdict:** Confirmed
- **Severity:** Low
- **Reach:** All platforms. Needs a non-empty listening queue or history at a vault switch. Uncommon.
- **Trigger:** The person queues `Week 3.md` in vault A, switches to vault B, and reads any note to its end, or taps "previous item".
- **Path:**
  1. On a switch, `openVault` calls only `readAloud.clear()` ([WorkspaceModel.swift:306](../../Sources/GraphiteUI/WorkspaceModel.swift#L306)). That resets the controller ([ReadAloudController.swift:424-443](../../Sources/GraphiteUI/ReadAloudController.swift#L424-L443)) but not the navigator's `queue` and `history` ([ReadAloudNavigator.swift:19-21](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L19-L21)). These change only through queue actions ([ReadAloudNavigator.swift:286-317](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L286-L317)).
  2. When reading finishes, `advance()` runs ([ReadAloudNavigator.swift:402-406](../../Sources/GraphiteUI/ReadAloudNavigator.swift#L402-L406)) and calls `startReading(next.path, …)` with A's path. The handler opens it in B ([WorkspaceModel.swift:1457-1458](../../Sources/GraphiteUI/WorkspaceModel.swift#L1457-L1458)).
  3. Outcome: B's same-named note is read aloud, or an error says the file cannot be opened.
- **Minimal fix:** Add `readAloudNavigator.reset()` to clear `queue`, `history` and pen marks, and call it beside `readAloud.clear()` in `openVault`.
- **Rule that prevents the class:** *New rule* (as for BUG-ARCH-03): vault-scoped state lives in one per-vault container that is replaced on a switch.
- **Aliases:** none
- **Verifier notes:** Found while tracing BUG-ARCH-07.

#### BUG-ARCH-V02 Callouts folded or expanded in one vault stay so in a same-named note of the next vault
- **Verdict:** Confirmed
- **Severity:** Low
- **Reach:** All platforms. Within one app session after a vault switch, for notes whose paths match. Cosmetic, but Read Aloud also skips the folded callouts.
- **Trigger:** In vault A the person collapses a callout in `Lecture.md`, switches to vault B, and opens B's `Lecture.md`.
- **Path:**
  1. `CalloutFoldStore` keeps expansion keyed by note path alone, for the session ([CalloutFoldStore.swift:9-20](../../Sources/GraphiteUI/CalloutFoldStore.swift#L9-L20)). The workspace owns one instance as a `let` ([WorkspaceModel.swift:182](../../Sources/GraphiteUI/WorkspaceModel.swift#L182)).
  2. The reset in `openVault` does not clear it ([WorkspaceModel.swift:303-323](../../Sources/GraphiteUI/WorkspaceModel.swift#L303-L323)).
  3. B's note reads `calloutFolds.expansion(for: path.rawValue)` in the editor ([MarkdownPane.swift:128-131](../../Sources/GraphiteUI/MarkdownPane.swift#L128-L131)) and for Read Aloud ([WorkspaceTabs.swift:352-354](../../Sources/GraphiteUI/WorkspaceTabs.swift#L352-L354), [WorkspaceModel.swift:1460-1461](../../Sources/GraphiteUI/WorkspaceModel.swift#L1460-L1461)).
- **Minimal fix:** Replace `calloutFolds` with a fresh store in `openVault`, or key it by vault identifier and path. Follow renames as `followMoveInFolds` does.
- **Rule that prevents the class:** *New rule* (as for BUG-ARCH-03): vault-scoped state lives in one per-vault container that is replaced on a switch.
- **Aliases:** none
- **Verifier notes:** Found while checking which vault-scoped state `openVault` resets. The store does not follow renames either; there is no call in `followMoveInNavigation` ([WorkspaceModel.swift:1201-1213](../../Sources/GraphiteUI/WorkspaceModel.swift#L1201-L1213)).

## Index

| ID | Area | Verdict | Severity |
| --- | --- | --- | --- |
| BUG-SHELL-01 | SHELL | Confirmed | Medium |
| BUG-SHELL-02 | SHELL | Confirmed | Low |
| BUG-SHELL-03 | SHELL | Confirmed | High |
| BUG-SHELL-04 | SHELL | Confirmed | Low |
| BUG-SHELL-05 | SHELL | Confirmed | Low |
| BUG-SHELL-06 | SHELL | Confirmed | Low |
| BUG-EDITOR-01 | EDITOR | Confirmed | Medium |
| BUG-EDITOR-02 | EDITOR | Confirmed | Medium |
| BUG-EDITOR-03 | EDITOR | Confirmed | Low |
| BUG-EDITOR-04 | EDITOR | Confirmed | Medium |
| BUG-READING-01 | READING | Confirmed | Medium |
| BUG-READING-02 | READING | Confirmed | Medium |
| BUG-READING-03 | READING | Confirmed | Medium |
| BUG-READING-04 | READING | Confirmed | Low |
| BUG-READING-05 | READING | Confirmed | Low |
| BUG-MDCORE-01 | MDCORE | Confirmed | High |
| BUG-MDCORE-02 | MDCORE | Confirmed | Medium |
| BUG-MDCORE-03 | MDCORE | Confirmed | Low |
| BUG-MDCORE-04 | MDCORE | Confirmed | Medium |
| BUG-MDCORE-05 | MDCORE | Plausible | Medium |
| BUG-MDCORE-06 | MDCORE | Confirmed | Low |
| BUG-VAULT-01 | VAULT | Confirmed | Medium |
| BUG-VAULT-02 | VAULT | Confirmed | Medium |
| BUG-VAULT-03 | VAULT | Confirmed | Low |
| BUG-BASES-01 | BASES | Confirmed | Low |
| BUG-BASES-02 | BASES | Confirmed | Low |
| BUG-BASES-03 | BASES | Confirmed | Medium |
| BUG-BASES-04 | BASES | Confirmed | Low |
| BUG-BASES-05 | BASES | Confirmed | Low |
| BUG-CANVAS-01 | CANVAS | Confirmed | High |
| BUG-CANVAS-02 | CANVAS | Confirmed | Medium |
| BUG-CANVAS-03 | CANVAS | Confirmed | Medium |
| BUG-CANVAS-04 | CANVAS | Confirmed | Low |
| BUG-CANVAS-05 | CANVAS | Confirmed | Low |
| BUG-CANVAS-06 | CANVAS | Confirmed | Low |
| BUG-INK-01 | INK | Confirmed | Medium |
| BUG-INK-02 | INK | Confirmed | Medium |
| BUG-INK-03 | INK | Confirmed | Medium |
| BUG-INK-04 | INK | Confirmed | Low |
| BUG-LECTURE-01 | LECTURE | Confirmed | Medium |
| BUG-LECTURE-02 | LECTURE | Confirmed | Low |
| BUG-LECTURE-03 | LECTURE | Confirmed | Low |
| BUG-LECTURE-04 | LECTURE | Confirmed | Low |
| BUG-VOICE-01 | VOICE | Confirmed | Medium |
| BUG-VOICE-V01 | VOICE | Confirmed | High |
| BUG-VOICE-L01 | VOICE | Confirmed | Low |
| BUG-VOICE-02 | VOICE | Confirmed | Low |
| BUG-VOICE-03 | VOICE | Confirmed | Medium |
| BUG-VOICE-04 | VOICE | Confirmed | Medium |
| BUG-VOICE-05 | VOICE | Confirmed | Medium |
| BUG-VOICE-06 | VOICE | Confirmed | Low |
| BUG-VOICE-07 | VOICE | Confirmed | Medium |
| BUG-VOICE-08 | VOICE | Confirmed | Medium |
| BUG-VOICE-09 | VOICE | Confirmed | Low |
| BUG-VOICE-10 | VOICE | Confirmed | Medium |
| BUG-PLUGIN-01 | PLUGIN | Confirmed | Medium |
| BUG-PLUGIN-02 | PLUGIN | Confirmed | Medium |
| BUG-PLUGIN-03 | PLUGIN | Confirmed | Medium |
| BUG-PLUGIN-04 | PLUGIN | Confirmed | Medium |
| BUG-PLUGIN-05 | PLUGIN | Plausible | Medium |
| BUG-PLUGIN-06 | PLUGIN | Confirmed | Medium |
| BUG-RUNTIME-01 | RUNTIME | Confirmed | High |
| BUG-RUNTIME-02 | RUNTIME | Confirmed | Medium |
| BUG-RUNTIME-03 | RUNTIME | Confirmed | Medium |
| BUG-RUNTIME-04 | RUNTIME | Confirmed | Low |
| BUG-RUNTIME-05 | RUNTIME | Refuted | Low |
| BUG-RUNTIME-06 | RUNTIME | Plausible | Low |
| BUG-RUNTIME-07 | RUNTIME | Confirmed | Low |
| BUG-RUNTIME-V01 | RUNTIME | Plausible | Low |
| BUG-ARCH-01 | ARCH | Confirmed | Low |
| BUG-ARCH-02 | ARCH | Confirmed (alias of BUG-SHELL-03) | High |
| BUG-ARCH-03 | ARCH | Plausible | Low |
| BUG-ARCH-04 | ARCH | Confirmed | Low |
| BUG-ARCH-05 | ARCH | Confirmed | Low |
| BUG-ARCH-06 | ARCH | Confirmed (alias of BUG-SHELL-02) | Low |
| BUG-ARCH-07 | ARCH | Confirmed | Medium |
| BUG-ARCH-V01 | ARCH | Confirmed | Low |
| BUG-ARCH-V02 | ARCH | Confirmed | Low |

## Found after the snapshot

The delta audits of 2026-10-19 (code changed between `b13dec3` and `9040705`) and 2026-10-20 (`9040705` to `5aae924`) found ten defects. Each is written up in section 9 of its area document; the lead traced the three marked "lead".

| ID | Area | Verdict | Severity | Defect |
| --- | --- | --- | --- | --- |
| [BUG-SHELL-07](areas/shell.md#the-notebook-library-9040705) | SHELL | **Fixed** in `bf86b5d`; Confirmed (lead) | High | A damaged `.obsidian/graphite-folder-styles.json` makes every folder of the library show "Can't Show This Folder" |
| [BUG-SHELL-08](areas/shell.md#the-notebook-library-9040705) | SHELL | **Fixed** in `bf86b5d`; Confirmed | Medium | A file that changes while its tile is on screen keeps its old preview |
| [BUG-SHELL-09](areas/shell.md#the-notebook-library-9040705) | SHELL | **Fixed** in `bf86b5d`; Confirmed (the effect on visible previews is Plausible) | Medium | A tile's preview keeps rendering after the tile scrolls away, with no limit on concurrent renders |
| [BUG-SHELL-10](areas/shell.md#other-shell-changes-fff794b) | SHELL | **Fixed** in `a2b32ab`; Confirmed (lead) | Medium | When a vault's Templates or Daily notes settings cannot be read, the previous vault's settings stay in force and can create a daily note in the new vault |
| [BUG-SHELL-11](areas/shell.md#other-shell-changes-fff794b) | SHELL | **Fixed** in `b4d1e17`; Confirmed | Low | A plugin's rename is answered "not renamed" when the move takes longer than 10 s after the person answers |
| [BUG-SHELL-12](areas/shell.md#other-shell-changes-fff794b) | SHELL | **Fixed** in `613c24d`; Confirmed | Low | `graphite://read?file=X` reads nothing when X is already open on the other side of the split |
| [BUG-VOICE-11](areas/voice.md#9-since-the-snapshot) | VOICE | **Fixed** in `1b6f5ae`; Confirmed (lead) | Medium | Pronunciation Settings overwrite terms that reached the vault file after the page opened |
| [BUG-VOICE-12](areas/voice.md#9-since-the-snapshot) | VOICE | Plausible (a device check settles it); open, see [status.md](status.md) | Low | Connecting headphones pauses High Quality reading whenever the engine reconfigures |
| [BUG-IMPORT-01](areas/import.md#bug-import-01-a-goodnotes-notebook-without-its-event-log-opens-as-an-empty-notebook-with-no-issue) | IMPORT | **Fixed** in `471de62`; Confirmed (lead) | Medium | A Goodnotes notebook without its event log opens as an empty notebook with no issue (latent: the readers are not wired into the app) |
| [BUG-IMPORT-02](areas/import.md#bug-import-02-a-negative-stored-page-width-gives-a-notability-pagecount-below-1-breaking-its-at-least-1-contract) | IMPORT | **Fixed** in `471de62`; Confirmed (lead) | Low | A negative stored page width gives a Notability `pageCount` below 1 (latent) |

`BUG-SHELL-07`, `-08` and `-09` are fixed with regression tests in `bf86b5d`; `BUG-SHELL-10` in `a2b32ab` and `BUG-VOICE-11` in `1b6f5ae`, each with a regression test ([status.md](status.md)). `BUG-SHELL-11` and `-12` are fixed with regression tests in `b4d1e17` and `613c24d` (2026-10-20); every other Low defect fixed that day is recorded in [status.md](status.md). The snapshot defects above keep their verdicts; their state is in [status.md](status.md) (`BUG-MDCORE-05` fixed in `9a96593`, `BUG-PLUGIN-05` in `1a0f5d0`).
