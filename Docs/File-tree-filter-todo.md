# Filter the file tree by name: implementation TODO

Created: 2026-10-24.

Status: not started. Issue: [#103](https://github.com/Graphite-Note/Graphite/issues/103) (section 1).

## Request

The owner, 2026-10-24, with a screenshot of Obsidian's file list: a field above the tree holds "bati", a clear button with the tooltip "Clear search" sits at its end, and the tree below keeps only the folder "Batikha-hour", still expandable in place. "another feature request is here to find just the folder listed": typing part of a name narrows the file tree to the folders and files whose names match, so a folder is found and opened without scrolling a 30,000-file vault.

## What exists today (2026-10-24)

- The sidebar's search field (`.searchable` on `workspace.searchQuery` in `Sources/GraphiteUI/VaultSidebar.swift`) runs the index's full-text search (`WorkspaceModel.search()`, `VaultIndex.search`) and replaces the tree with a flat list of results, sorted by the search sort order.
- A result is a file with its matching lines (`SearchResult` in `Sources/GraphiteIndex/VaultSearch.swift`); a folder is never a result, so a folder can only be found by scrolling and expanding the tree (`FileTreeRows`, `MacFileTree`).

## Decision

- The filter reuses the sidebar's existing search field rather than adding a second field above the tree, which would cost a row of the sidebar (screen space over chrome). In the Files panel a query first shows the tree filtered by name, then the full-text results below it. This is the recommendation; the owner may prefer a separate field as in Obsidian's screenshot.

## 1. Folders and files matching the typed name, in the tree

Issue: [#103](https://github.com/Graphite-Note/Graphite/issues/103)

- [ ] In the Files panel, a query shows the file tree keeping only the folders and files whose name contains the query (case- and accent-insensitive), each with the folders above it, those folders expanded; a matching folder stays collapsed and expandable with its whole content, as in the owner's screenshot.
- [ ] The matched part of each name is highlighted; the full-text results stay listed below the tree under their "Results" header, so nothing the search finds today is lost.
- [ ] Choosing a folder expands it and keeps it visible after the query is cleared; choosing a file opens it as today. The clear button empties the field and returns the tree as it was, with its expanded folders.
- [ ] Matched by name only, from the paths the workspace already lists or the index's file table, never by reading files; filtering a 30,000-file vault answers within one frame of a keystroke on the iPad (a timing budget in `App/Tests/TimingBudgets.swift`).
- [ ] Same behavior on the Mac's outline (`MacFileTree`) and the iPad and iPhone list (`FileTreeRows`), including keyboard: arrow keys move through the filtered rows, Return opens.
- [ ] Tests: Core or Index tests of the name match (case, accents, nested folders, a folder and a file of one name); hosted tests that typing a folder's partial name shows that folder in the tree and that clearing restores the expanded folders.
- [ ] Checked on the Mac and the iPad with the owner's vault (finding "Batikha-hour" by "bati").
