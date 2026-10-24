# Filter the file tree by name: implementation TODO

Created: 2026-10-24.

Status: not started. Issue: [#103](https://github.com/Graphite-Note/Graphite/issues/103) (section 1), [#104](https://github.com/Graphite-Note/Graphite/issues/104) (section 2).

## Request

The owner, 2026-10-24, with a screenshot of Obsidian's file list: a field above the tree holds "bati", a clear button with the tooltip "Clear search" sits at its end, and the tree below keeps only the folder "Batikha-hour", still expandable in place. "another feature request is here to find just the folder listed": typing part of a name narrows the file tree to the folders and files whose names match, so a folder is found and opened without scrolling a 30,000-file vault.

## What exists today (2026-10-24)

- The sidebar's search field (`.searchable` on `workspace.searchQuery` in `Sources/GraphiteUI/VaultSidebar.swift`) runs the index's full-text search (`WorkspaceModel.search()`, `VaultIndex.search`) and replaces the tree with a flat list of results, sorted by the search sort order.
- A result is a file with its matching lines (`SearchResult` in `Sources/GraphiteIndex/VaultSearch.swift`); a folder is never a result, so a folder can only be found by scrolling and expanding the tree (`FileTreeRows`, `MacFileTree`).

## Decision

- The owner, 2026-10-24, chose a field of its own over reusing the sidebar's search field: "Option B". The Files panel gets a filter field above the tree, as in Obsidian's screenshot, used only to find files and folders by name. The sidebar's search field stays as it is, a full-text search. The field costs one row of the sidebar, accepted by the owner over the screen-space rule.

## 1. Folders and files matching the typed name, in the tree

Issue: [#103](https://github.com/Graphite-Note/Graphite/issues/103)

- [ ] A filter field of its own at the top of the Files panel, under the panel's buttons and above the tree, with a magnifier, a "Filter" placeholder and a clear button whose tooltip is "Clear Filter", as in the owner's screenshot. It shows in the Files panel only; the sidebar's search field and its full-text results are unchanged.
- [ ] Typing in it keeps only the folders and files whose name contains the text (case- and accent-insensitive), each with the folders above it, those folders expanded; a matching folder stays collapsed and expandable with its whole content, as in the owner's screenshot. The matched part of each name is highlighted.
- [ ] Choosing a folder expands it and keeps it visible after the filter is cleared; choosing a file opens it as today. The clear button or Escape empties the field and returns the tree as it was, with its expanded folders. A command (and a keyboard shortcut on the Mac and the iPad keyboard) puts the cursor in the field.
- [ ] Matched by name only, from the paths the workspace already lists or the index's file table, never by reading files; filtering a 30,000-file vault answers within one frame of a keystroke on the iPad (a timing budget in `App/Tests/TimingBudgets.swift`).
- [ ] Same behavior on the Mac's outline (`MacFileTree`) and the iPad and iPhone list (`FileTreeRows`), including keyboard: arrow keys move through the filtered rows, Return opens.
- [ ] Tests: Core or Index tests of the name match (case, accents, nested folders, a folder and a file of one name); hosted tests that typing a folder's partial name in the filter field shows that folder in the tree, that clearing restores the expanded folders, and that the sidebar's search is unaffected.
- [ ] Checked on the Mac and the iPad with the owner's vault (finding "Batikha-hour" by "bati").

## 2. `folder:` in the sidebar's search

Issue: [#104](https://github.com/Graphite-Note/Graphite/issues/104)

The owner, 2026-10-24, after choosing the separate field: "and a folder: in the original". The sidebar's existing search also finds folders, through a `folder:` operator next to Obsidian's `path:`, `file:` and `tag:` (`SearchScope` in `Sources/GraphiteCore/SearchQuery.swift`). Obsidian has no `folder:`; Graphite adds it.

- [ ] `folder:bati` lists the folders whose name contains "bati" (same matching as section 1) as results of their own, above any notes, each with its path; `folder:"Batikha hour"` and `folder:/regex/` work as for `file:`.
- [ ] Choosing a folder result reveals it in the file tree, expanded and selected, and clears the search; its context menu offers Reveal in File Tree and the folder's usual actions.
- [ ] `folder:` combined with other terms narrows notes to those inside the matching folders (`folder:bati steak` finds notes mentioning steak in those folders), as `path:` does for a path.
- [ ] Offered in the search field's suggestions with the other operators, and described in the search help and the Guide.
- [ ] Tests: Core tests that `folder:` parses like the other scopes; index tests that it returns folders, nested and accented names included, and narrows notes when combined; a hosted test that choosing a folder result reveals it in the tree.
- [ ] Checked on the Mac and the iPad with the owner's vault.
