# Multiple windows on iPad and Mac: TODO

Created: 2026-10-21.

Status: not started. The iPad has one scene (`UIApplicationSupportsMultipleScenes` is false in `App/Info.plist`) and the Mac one `Window` with identifier `"main"` (`Sources/GraphiteUI/GraphiteMacScenes.swift`), on purpose: each window builds its own `WorkspaceModel`, which reopens the last vault with its own index on the same cache file, recorder and autosave, so two of them would fail each other's index writes ("database is locked") and delete each other's rows on rescan. The owner decided on 2026-10-18 that Graphite will run several windows per process (decision 12 in [rewrite-foundations.md](solid/rewrite-foundations.md) section 13); this checklist is that feature.

## Request

Open more than one Graphite window at once: on the iPad in Stage Manager and Split View, on the Mac as ordinary windows and window tabs. Typical uses: a lecture PDF in one window and its note in another, two notes side by side across displays, two vaults open at once.

## Scope

- [ ] Scene split before Phase 6 of the plan: process services (index, vault library, plugin runtime, voices, add-on library) shared by every window; scene services (workspace, tabs, Pencil activity, embedded-PDF registry, presentation state, alerts) per window. `ARCH-INV-08` and the single-window part of `N-11` are retired, struck through with that reason, when it lands.
- [ ] One index per vault, whatever the number of windows: windows on the same vault share one `VaultIndex` behind a single-writer actor; a vault's index closes when its last window does. Two vaults in two windows each keep their own.
- [ ] Process-wide singletons that hold one window's state become per scene or are checked safe to share: `EmbeddedPDFSessions.shared`, `PencilToolbox.shared`, `PaletteToolChoiceObserver.shared`, `DocumentPlaceStore.shared`, `DrawingEditorDraftStore.shared`, `GraphiteApplicationDelegate.workspaceToSave`.
- [ ] The same file open in two windows: both show the edits of either without a reload, and neither save overwrites the other (file coordination, one in-memory document per file).
- [ ] One recording and one Read Aloud at a time across all windows; starting one in a second window says where the first is running.
- [ ] Mac: File › New Window (⌘N stays New Note; ⌥⌘N or the system's default for the window), window tabs, quitting waits for every window's saves (still at most 5 s) and answers the application once. Settings and the Guide stay single windows.
- [ ] iPad: `UIApplicationSupportsMultipleScenes` true; "Open in New Window" in the context menu of files, tabs and links; dragging a tab or a file out of the sidebar opens it in a new window; the app switcher shows each window with its note's title.
- [ ] Each window restores its own vault, tabs and layout after relaunch (scene state, not the shared device defaults).
- [ ] A setting changed in Settings reaches every open window at once.
- [ ] Tests: two workspaces on one vault index without "database is locked" and without losing rows on rescan; the same note edited in two windows keeps both edits; closing one window releases its scene services and keeps the shared index; quitting with two windows saves both; `EX-02` updated for the plist key.
- [ ] On the iPad in Stage Manager and on the Mac: two windows on one vault, two windows on two vaults, a PDF and its note side by side, Pencil in one window while typing in the other.
- [ ] Each window costs nothing beyond its own views when unused: memory of a second idle window measured against one.
- [ ] `Architecture.md`, `Coverage.md`, [Obsidian-mobile-gaps.md](Obsidian-mobile-gaps.md) (the Multiple windows row) and `Docs/solid/invariants.md` updated once built and tested; `python3 scripts/size-report.py` passes.

## Open questions

- Mac shortcut for a new window, since ⌘N is New Note?
- Two vaults open at once, or every window on the same vault (simpler: one index)?
- iPhone stays one window; anything to change there (for example the iPhone Mirroring or external display case)?
