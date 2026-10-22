# Graph view: TODO

Created: 2026-10-21.

Priority: high. The owner asked for it on 2026-10-21, looking at his vault's graph on the Mac: "improve drastically, make it more accessible, not through view then graph view, make tags available and make it just look nicer".

Status: the graph itself ships and is correct. `LinkGraph`, `GraphLinkResolver` and `GraphLayout` build it, `VaultGraphScreen`, `LocalGraphPanel` and `GraphCanvas` draw it, `LinkGraphTests`, `VaultGraphTests` and `GraphLinkResolverTests` cover it, and it was checked on the iPad on 2026-09-24 (`Coverage.md`). Nothing in this file is built yet: it is about reaching the graph, tags in it, how it looks, and how it behaves on a vault the owner's size.

## Request

Today the whole-vault graph is reached through View › Graph View on the Mac or "Graph view: Open graph view" in the command palette, and it opens as a modal: a page-sized sheet on the Mac, a full-screen cover on iPadOS (`GraphiteRootView`, `workspace.isGraphPresented`). It closes as soon as a note is opened from it. Tags are off by default and their toggle sits inside the Graph Settings popover. The drawing is plain: gray notes, links at 18 percent, names only from a zoom of 1.4, no colored groups.

The owner wants it one tap away, tags there without hunting for them, and a graph that is good to look at on a vault of about 4,700 notes.

## Decisions

- It stays Obsidian's graph: the same links, filters and forces, read from the same index. This file is about the way in, tags and the look, not a second graph.
- Its settings stay on the device (`GraphSettingKey` in `WorkspaceGraph.swift`), as Obsidian keeps them in its workspace. Nothing new is written into the vault.
- Groups are Obsidian's groups: a search and a color, not a new file format.
- The look follows Graphite's theme and accent colors, not Obsidian's palette.

## 1. Ways in

- [x] The whole-vault graph opens as a tab of the workspace, as a note does, instead of the modal it is today. It can sit beside a note in a split, it stays open while notes are opened from it, and a window restores it with its other tabs (`TabLayout`, `GraphiteWindows`).
  Done 2026-10-22: a tab can show a core plugin's view in place of a file (`WorkspaceTab.CoreView.graph`, Core), saved with the layout as `"coreView": "graph"` (a view a newer build saved and this one does not know restores an empty tab). `WorkspaceModel.showGraph()` brings the graph's tab forward, else shows it in the empty tab in front, else in a new tab; `VaultGraphView` draws it there with the filter, Show All and settings over its top, the file opened last highlighted. The sheet and full-screen cover are gone; View › Graph View and the palette open the tab. A file opened while the graph is in front goes to another tab, as from a pinned tab. Tests: `TabLayoutTests` (4 new: a tab of its own, the empty tab, beside it, saved and restored), `WorkspaceGraphTabTests` (4). Seen in the iPad simulator: the graph in a tab beside the open notes, and the window brought it back with them after a relaunch. Not seen by hand on the Mac.
- [x] Opening a node from a graph tab opens the note on the other side of the split, or in the neighboring tab, and leaves the graph where it is; today the sheet is dismissed first (`VaultGraphScreen`'s open closure).
  Done 2026-10-22: `TabLayout.tabForOpening(besideTab:)`, as `TabPlacement.besideTab`: split, the other side's active tab (a new tab there when it is pinned or shows a view); else the tab right of the graph, then the one left of it, a new tab right of the graph when neither may change file. A note open in a tab already comes forward there. Tests: `TabLayoutTests.testANoteOpenedFromTheGraphGoesBesideIt`, `WorkspaceGraphTabTests`.
- [ ] A graph button in the left sidebar's header row, beside Settings and New, so the graph is one tap from the file list. No new row: every row above the page is waste.
- [ ] Default keyboard shortcuts. `graph:open` and `graph:open-local` have none (`GraphiteCommand`): give the whole-vault graph ⌘⇧G, which is free, and the local graph a combination beside it, both still changeable in Settings › Keyboard Shortcuts.
- [ ] A note's More menu opens its local graph, and the local graph panel offers to open the whole graph centered on that note.
- [ ] "Show in Graph" on a tag in the Tags panel and on a folder in Files, opening the graph filtered to it (the filter the search field takes today).
- [ ] View › Graph View on the Mac and the palette's commands stay as they are; `GuideCopyOrganizing` is updated to the ways in that come out of this.

## 2. Tags in the graph

- [ ] Tags shown by default, in the whole-vault graph and in the local graph (`graphShowsTags` and `localGraphShowsTags`, both off today).
- [ ] A Tags toggle in the graph's own toolbar, not only inside the Graph Settings popover.
- [ ] Nested tags: decide whether `#course/vlsi` also draws `#course` and links the two, as the Tags panel nests them, or whether the written tags alone keep the graph readable. The index gives the written tags today (`VaultGraph.linkGraph`). Whichever is chosen is written here and in `Coverage.md`.
- [ ] Tag nodes drawn as tags: their green, a size from how many notes carry them, and their name shown at a lower zoom than a note's.
- [ ] Choosing a tag in the graph highlights its notes instead of closing the graph for the search field (`WorkspaceModel.open(_:from:)` sets a `tag:` search today); searching for it stays on its menu.
- [ ] The count at the corner names what it counts, tags included ("4,700 notes · 699 tags · 1,690 links"), rather than "items".

## 3. A graph worth looking at

- [ ] Obsidian's groups: colored groups from a search, added and removed in the graph's settings and kept per vault with the other graph settings; every node a group matches takes its color. The owner's vault is mostly courses, so a group per course is the first thing he will make.
- [ ] The display settings Obsidian has and Graphite lacks, each beside Arrows: node size, link thickness, and the zoom at which names appear (`GraphCanvas.labelScale`, 1.4 today).
- [ ] Names fade in rather than appearing all at once, and never overlap: at the drawn scale a name is left out when it would cover one already drawn.
- [ ] The node under the finger or the pointer keeps its neighbors bright and dims the rest, as it does today, and the open note keeps a halo in the accent color so it can be found in a vault this size.
- [ ] Colors chosen for light and dark against Graphite's accent colors: links are black or white at 18 percent today, notes plain secondary, attachments amber, tags green, and a link without a file looks like a note although it is not one.
- [ ] The first drawing is calm: the graph opens at the zoom and the positions it was left at (`workspace.graphPositions`) and settles from there, instead of appearing mid-flight.

## 4. A vault of this size

- [ ] Measure first, on the Mac and on the iPad, with tags on and off: time to the first drawing, time to a settled layout, and the frame rate while dragging and pinching. The numbers go in this file.
- [ ] A vault of about 4,700 notes settles in a couple of seconds, and nothing blocks the main thread while it does (the simulation already steps in an actor off the main thread).
- [ ] The forces' defaults are tuned on a vault that size rather than on the test vault, so clusters stay apart and the ring of notes without links does not take the outer third of the screen, as it does in the owner's photo of 2026-10-21.
- [ ] A very large vault (100,000 notes) stays usable; it takes about half a minute to settle today (`Obsidian-mobile-gaps.md`).
- [ ] Drawing cost at this size: nodes gathered into one path per color where that measures faster than a path each.

## 5. Verification

- [ ] Unit tests: a group filters and colors the nodes its search matches; the tag defaults; a name left out because another covers it; the count line.
- [ ] Hosted tests on the iPad simulator: the graph as a tab, split beside a note, restored with the window; a node opened from it without the graph closing.
- [ ] Screenshots before and after, in light and dark, of the test vault and of a small demo vault. Never the owner's personal notes.
- [ ] On the owner's iPad and Mac, with his vault: every way in, tags on, a group per course, and the numbers of section 4.
- [ ] `Architecture.md`, `Coverage.md`, `Obsidian-mobile-gaps.md` and `Docs/solid/invariants.md` updated as parts are built, and `python3 scripts/size-report.py` passes.
