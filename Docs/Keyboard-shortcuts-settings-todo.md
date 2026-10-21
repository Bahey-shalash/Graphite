# Keyboard shortcuts in Settings: TODO

Created: 2026-10-21.

Status: not started. Shortcuts are fixed in code, in three places that do not know about each other: the menu commands in `GraphiteCommands.swift` (`.keyboardShortcut`, about 20), the editor's `editorShortcuts` in `NativeMarkdownEditor.swift` (`UIKeyCommand`), and the command palette's `WorkspaceCommandList`, which repeats some of them as display text (`shortcut: "⌘O"`) that can drift from the real ones. A few views add their own (`TableCellTextField`, `CanvasPane`, `QuickPalette`, `WelcomeTour`). [Obsidian-mobile-gaps.md](Obsidian-mobile-gaps.md) lists "Settings search, hotkey and toolbar settings" as missing.

## Request

A page in Settings, on the Mac and the iPad, that lists Graphite's commands with their shortcuts and lets the user change, add or remove them. When a shortcut clashes with the system, or with another Graphite command, the page says so next to it.

## Scope

- [ ] One list of commands: each has a stable identifier (Obsidian's command id where one matches, such as `editor:toggle-bold`), a title, a group (File, View, Go, Editor, Canvas, plugins) and its default shortcut. The menus, the editor's key commands and the palette all read their shortcut from it, so the palette shows the shortcut that actually works.
- [ ] Settings › Keyboard Shortcuts: the commands by group, a search field (by title or by shortcut), each row with its shortcut, a button to record a new one, remove, and reset to default; Reset All at the bottom. On the Mac a pane of the Settings window, on the iPad a page of Settings.
- [ ] Recording: the next key press with its modifiers becomes the shortcut; Escape cancels. A key without ⌘, ⌃ or ⌥ is refused unless it is a function key, so typing is never taken over.
- [ ] Conflicts with another Graphite command: both rows are marked; assigning a shortcut that is in use asks whether to move it (the other command loses it) or cancel.
- [ ] Conflicts with the system, from a table in Graphite for each platform, in three kinds:
  - Taken by the system, never reaches Graphite (macOS: ⌘Tab, ⌘Space, ⌃Space, ⇧⌘3, ⇧⌘4, ⇧⌘5, ⌃⌘Q, ⌥⌘D, ⌥⌘Esc, Mission Control's ⌃ arrows; iPadOS: ⌘H, ⌘Space, ⌘Tab, the Globe key's shortcuts). Refused, with the reason shown.
  - Standard in every app (⌘Q, ⌘H, ⌘M, ⌘` for windows, ⌘C, ⌘V, ⌘X, ⌘Z, ⇧⌘Z, ⌘A, ⌘, for Settings). Allowed after a warning that other apps use it for that.
  - Graphite's own default for another command: covered by the item above.
  The table is checked by hand on macOS 27 and iPadOS 27 against Apple's keyboard shortcut lists, and its source is noted in the code.
- [ ] Mac: shortcuts the user set in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts (`NSUserKeyEquivalents`, for Graphite or for all apps) override the menu's. The page shows them on their rows as "set in System Settings". Check whether a sandboxed Graphite can also read the user's changes to the system's own shortcuts; if not, the page says the table covers only the system's defaults.
- [ ] Keyboard layouts: shortcuts are stored by the key's character as Obsidian does; check them on the Swiss French layout on both devices, where `/`, `[`, `]` and `` ` `` need ⌥ or ⇧ (on the Mac, `allowsAutomaticKeyEquivalentLocalization`).
- [ ] Storage: changes only (not the defaults) in the vault's `.obsidian/hotkeys.json`, Obsidian's format (`{"editor:toggle-bold": [{"modifiers": ["Mod"], "key": "B"}]}`, `Mod` being ⌘), so a vault keeps the same shortcuts in Obsidian and in Graphite. Entries for commands Graphite does not have are kept untouched when the file is written. A damaged file is reported and the defaults apply; it is never overwritten.
- [ ] Community plugins: commands added with `addCommand` appear in their plugin's group, with their declared `hotkeys` as defaults, and can be changed like the others. They leave the list when the plugin is turned off.
- [ ] Costs nothing while unused: the list is built when the page opens; key handling looks shortcuts up in a table built once per change.
- [ ] Tests: every menu, editor and palette shortcut comes from the list; a change in `hotkeys.json` reaches the menu and the editor; a clash between two commands is found; each kind of system clash is found from the table; an unknown command's entry survives a write; a damaged file leaves the defaults and the file as they were.
- [ ] On the Mac and the iPad with a hardware keyboard: change ⌘B to another shortcut and use it in a note; try ⌘Tab and see it refused; try ⌘Q and see the warning; set a Graphite shortcut in System Settings and see it on the page.
- [ ] `Architecture.md`, `Coverage.md`, [Obsidian-mobile-gaps.md](Obsidian-mobile-gaps.md) and `Docs/solid/invariants.md` updated once built and tested; `python3 scripts/size-report.py` passes.

## Open questions

- Per vault in `.obsidian/hotkeys.json` (shared with Obsidian, and the same on every device that opens the vault), or per device?
- The iPhone with a hardware keyboard: the same page, or nothing?
