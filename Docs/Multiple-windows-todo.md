# Multiple windows on iPad and Mac: TODO

Created: 2026-10-21.

Status: not started. The iPad has one scene (`UIApplicationSupportsMultipleScenes` is false in `App/Info.plist`) and the Mac one `Window` with identifier `"main"` (`Sources/GraphiteUI/GraphiteMacScenes.swift`), on purpose: each window builds its own `WorkspaceModel`, which reopens the last vault with its own index on the same cache file, recorder and autosave, so two of them would fail each other's index writes ("database is locked") and delete each other's rows on rescan. The owner decided on 2026-10-18 that Graphite will run several windows per process (decision 12 in [rewrite-foundations.md](solid/rewrite-foundations.md) section 13); this checklist is that feature.

## Request

Open more than one Graphite window at once: on the iPad in Stage Manager and Split View, on the Mac as ordinary windows and window tabs. Typical uses: a lecture PDF in one window and its note in another, two notes side by side across displays, two vaults open at once. Windows may show the same vault or different ones (owner, 2026-10-21). The iPhone stays one window (owner, 2026-10-21).

## Scope

- [ ] Scene split before Phase 6 of the plan: process services (index, vault library, plugin runtime, voices, add-on library) shared by every window; scene services (workspace, tabs, Pencil activity, embedded-PDF registry, presentation state, alerts) per window. `ARCH-INV-08` and the single-window part of `N-11` are retired, struck through with that reason, when it lands.
- [x] One index per vault, whatever the number of windows: windows on the same vault share one `VaultIndex` behind a single-writer actor; a vault's index closes when its last window does. Two vaults in two windows each keep their own. Done 2026-10-21: `VaultIndexRegistry` in `ProcessServices` leases one index per vault and runs one scan at a time for all its windows (a scan asked for during another follows it; a window opening a vault another window scanned does not scan again; a rebuild empties and rescans for every window); a vault open in another window cannot be removed from the vault list. Tested by `SharedVaultIndexTests` (10 tests).
- [ ] Process-wide singletons that hold one window's state become per scene or are checked safe to share: `EmbeddedPDFSessions.shared`, `PencilToolbox.shared`, `PaletteToolChoiceObserver.shared`, `DocumentPlaceStore.shared`, `DrawingEditorDraftStore.shared`, `GraphiteApplicationDelegate.workspaceToSave`.
- [ ] The same file open in two windows: both show the edits of either without a reload, and neither save overwrites the other (file coordination, one in-memory document per file).
- [ ] One recording and one Read Aloud at a time across all windows; starting one in a second window says where the first is running.
- [ ] Mac: File › New Window with ⌥⌘N (⌘N stays New Note, as Mail keeps ⌘N for New Message and puts New Viewer Window on ⌥⌘N; the HIG gives ⌘N to a new document and fixes no other new-window shortcut), window tabs, quitting waits for every window's saves (still at most 5 s) and answers the application once. Settings and the Guide stay single windows.
- [ ] iPad: `UIApplicationSupportsMultipleScenes` true (iPad only; the iPhone keeps one scene); File › New Window with ⌥⌘N in the iPad menu bar as on the Mac; "Open in New Window" in the context menu of files, tabs and links; dragging a tab or a file out of the sidebar opens it in a new window; the app switcher shows each window with its note's title.
- [ ] Each window restores its own vault, tabs and layout after relaunch (scene state, not the shared device defaults).
- [ ] A setting changed in Settings reaches every open window at once.
- [ ] Tests: two workspaces on one vault index without "database is locked" and without losing rows on rescan; the same note edited in two windows keeps both edits; closing one window releases its scene services and keeps the shared index; quitting with two windows saves both; `EX-02` updated for the plist key.
- [ ] On the iPad in Stage Manager and on the Mac: two windows on one vault, two windows on two vaults, a PDF and its note side by side, Pencil in one window while typing in the other.
- [ ] Each window costs nothing beyond its own views when unused: memory of a second idle window measured against one.
- [ ] `Architecture.md`, `Coverage.md`, [Obsidian-mobile-gaps.md](Obsidian-mobile-gaps.md) (the Multiple windows row) and `Docs/solid/invariants.md` updated once built and tested; `python3 scripts/size-report.py` passes.

## Decisions

- New window: ⌥⌘N on the Mac and the iPad, following Mail (owner, 2026-10-21).
- Windows may show the same vault or different vaults (owner, 2026-10-21).
- Nothing for the iPhone; it stays one window (owner, 2026-10-21).
- The split and its order (owner, 2026-10-21): process services are the device defaults and one `GraphitePreferences`, the vault list, the application folders, the add-on library, the document-place store, a registry of open vaults (one shared `VaultStore`, `VaultMonitor`, `VaultIndex` and indexing run per vault, leased by each window and closed with its last one, which tells every window on the vault of saves and external changes), the Pencil toolbox, the drawing-draft store, Read Aloud's voices with one Read Aloud controller and one recorder (each records the window that owns it), and diagnostics. Scene services are the `WorkspaceModel` (tabs, selection, history, search, sidebar, alerts, presentation, layout), the embedded-PDF registry, the Pencil activity, the palette's lasso state and each window's place in a note. Order: (1) the split with one window, (2) one shared vault per vault, (3) the named singletons, (4) one recording and one Read Aloud, (5) the same note in two windows, (6) Mac windows, (7) iPad scenes, (8) restoration per window, (9) memory, documents and invariants.
- Community plugins: one runtime per open vault, shared by that vault's windows and acting on the frontmost of them, so a plugin never runs twice on the same files (owner, 2026-10-21).
- The same PDF, canvas or base in two windows: each window has its own copy; a save in one reloads the other at once when it has no unsaved changes, and otherwise offers today's conflict choice. Only notes share one live document (owner, 2026-10-21).
- New Window opens the vault of the window it came from, with an empty new tab (owner, 2026-10-21).
- The file presenter (`VaultMonitor`) and `VaultStore` stay one per window, a change from the split above: the system reports one window's coordinated writes to the other windows' presenters, so a save in one window reaches the others through the tested external-change path (reload when clean, conflict otherwise) and no write path needs a broadcast of its own. Only the index and its scans are shared (2026-10-21).
- A note open in two windows keeps one undo history per window; a change from the other window clears this window's undo history of that note, since its ranges no longer hold (proposed with the split, not objected to).
