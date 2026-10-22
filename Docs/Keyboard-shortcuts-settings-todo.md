# Keyboard shortcuts in Settings: TODO

Created: 2026-10-21.

Status: built and tested in the package on 2026-10-21; the checks with a hardware keyboard on a Mac and an iPad are not done yet (see the unticked items). Before, shortcuts were fixed in code, in three places that did not know about each other: the menu commands in `GraphiteCommands.swift`, the editor's `editorShortcuts` in `NativeMarkdownEditor.swift` and the command palette's `WorkspaceCommandList`, which repeated some of them as display text. Now one list, `GraphiteCommand`, holds them all (see `Docs/Architecture.md`, "Commands and shortcuts"). `TableCellTextField`'s Tab, Escape and arrows, `QuickPalette`'s arrows and `WelcomeTour`'s keys stay fixed: they move within a control and are not commands.

## Request

A page in Settings, on the Mac and the iPad (not the iPhone), that lists Graphite's commands with their shortcuts and lets the user change, add or remove them. When a shortcut clashes with the system, or with another Graphite command, the page says so next to it.

## Scope

Issue: [#55](https://github.com/Graphite-Note/Graphite/issues/55)

- [x] One list of commands: each has a stable identifier (Obsidian's command id where one matches, such as `editor:toggle-bold`), a title, a group (File, View, Go, Editor, Canvas, plugins) and its default shortcut. The menus, the editor's key commands and the palette all read their shortcut from it, so the palette shows the shortcut that actually works.
- [x] Settings › Keyboard Shortcuts: the commands by group, a search field (by title or by shortcut), each row with its shortcut, a button to record a new one, remove, and reset to default; Reset All at the bottom. On the Mac a pane of the Settings window, on the iPad a page of Settings.
- [x] Recording: the next key press with its modifiers becomes the shortcut; Escape cancels. A key without ⌘, ⌃ or ⌥ is refused unless it is a function key, so typing is never taken over.
- [x] Conflicts with another Graphite command: both rows are marked; assigning a shortcut that is in use asks whether to move it (the other command loses it) or cancel.
- [x] Conflicts with the system, from a table in Graphite for each platform, in three kinds:
  - Taken by the system, never reaches Graphite (macOS: ⌘Tab, ⌘Space, ⌃Space, ⇧⌘3, ⇧⌘4, ⇧⌘5, ⌃⌘Q, ⌥⌘D, ⌥⌘Esc, Mission Control's ⌃ arrows; iPadOS: ⌘H, ⌘Space, ⌘Tab, the Globe key's shortcuts). Refused, with the reason shown.
  - Standard in every app (⌘Q, ⌘H, ⌘M, ⌘` for windows, ⌘C, ⌘V, ⌘X, ⌘Z, ⇧⌘Z, ⌘A, ⌘, for Settings). Allowed after a warning that other apps use it for that.
  - Graphite's own default for another command: covered by the item above.
  The table is checked by hand on macOS 27 and iPadOS 27 against Apple's keyboard shortcut lists, and its source is noted in the code.
  Done: `SystemKeyboardShortcuts` (Core) holds both tables, with Apple's "Mac keyboard shortcuts" (support.apple.com/102650) and "Learn iPad keyboard shortcuts" (support.apple.com/102393) noted as the source; read against those pages on 2026-10-21, not yet tried key by key on macOS 27 and iPadOS 27. iPadOS's Globe shortcuts are left out, since Graphite cannot record the Globe key; ⌘Q is in the iPad's standard list because of the app menu iPadOS's menu bar gives every app. A reserved shortcut never reaches Graphite while the system keeps it, so it can only be "seen refused" when the system's shortcut is turned off or when `hotkeys.json` (from Obsidian) holds it: the row then says the system uses it.
- [ ] Mac: shortcuts the user set in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts (`NSUserKeyEquivalents`, for Graphite or for all apps) override the menu's. The page shows them on their rows as "set in System Settings". Check whether a sandboxed Graphite can also read the user's changes to the system's own shortcuts; if not, the page says the table covers only the system's defaults.
  Built: `SystemSettingsAppShortcuts` reads `NSUserKeyEquivalents` (Graphite's and all apps') and the page shows it on the row whose Mac menu title it names (`UserKeyEquivalents`, Core, parses it; tested). Graphite is sandboxed and cannot read the system's own shortcut changes (`com.apple.symbolichotkeys`), so the page says the table covers the system's defaults. Not yet checked in the running app with a shortcut set in System Settings.
- [ ] Keyboard layouts: shortcuts are stored by the key's character as Obsidian does; check them on the Swiss French layout on both devices, where `/`, `[`, `]` and `` ` `` need ⌥ or ⇧ (on the Mac, `allowsAutomaticKeyEquivalentLocalization`).
  Not checked. Shortcuts are recorded and stored by the key typed without modifiers (`UIKey.charactersIgnoringModifiers`, `NSEvent.characters(byApplyingModifiers: [])`), so on Swiss French ⌘/ records as ⇧⌘7; menus keep SwiftUI's automatic key localization.
- [x] Storage, per vault (owner, 2026-10-21): changes only (not the defaults) in the vault's `.obsidian/hotkeys.json`, Obsidian's format (`{"editor:toggle-bold": [{"modifiers": ["Mod"], "key": "B"}]}`, `Mod` being ⌘), so a vault keeps the same shortcuts in Obsidian and in Graphite. Entries for commands Graphite does not have are kept untouched when the file is written. A damaged file is reported and the defaults apply; it is never overwritten.
- [x] Community plugins: commands added with `addCommand` appear in their plugin's group, with their declared `hotkeys` as defaults, and can be changed like the others. They leave the list when the plugin is turned off.
- [x] Costs nothing while unused: the list is built when the page opens; key handling looks shortcuts up in a table built once per change.
- [x] Tests: every menu, editor and palette shortcut comes from the list; a change in `hotkeys.json` reaches the menu and the editor; a clash between two commands is found; each kind of system clash is found from the table; an unknown command's entry survives a write; a damaged file leaves the defaults and the file as they were.
  Done: `KeyCombinationTests`, `HotkeyFileTests` (unknown entries survive a write; a damaged file and its bytes are left as they were), `KeyboardShortcutTableTests` (clash, move, reset, every kind of system clash), `UserKeyEquivalentsTests` (Core); `VaultKeyboardShortcutsTests` (the vault's file reaches the menu bar, the editor and the palette; recording; writing; damaged file; plugin commands), `GraphiteCommandTests`, `KeyboardShortcutsPageContentTests`, `CommunityPluginHostMessageContractTests` (UI); `plugin-identity.test.js` (Node). Run on the Mac in the package; the iPad build compiles but the hosted iPad suite was not run for this.
- [ ] On the Mac and the iPad with a hardware keyboard: change ⌘B to another shortcut and use it in a note; try ⌘Tab and see it refused; try ⌘Q and see the warning; set a Graphite shortcut in System Settings and see it on the page.
  Not done: no hardware-keyboard session on a device yet (and the simulator cannot hold ⌘). The Mac editor gained editing shortcuts with this work (it had none), so ⌘B in a note on the Mac is new there too.
- [x] `Architecture.md`, `Coverage.md`, [Obsidian-mobile-gaps.md](Obsidian-mobile-gaps.md) and `Docs/solid/invariants.md` updated once built and tested; `python3 scripts/size-report.py` passes.

## Decisions

- Shortcuts belong to the vault, in `.obsidian/hotkeys.json`, shared with Obsidian and the same on every device that opens the vault (owner, 2026-10-21).
- Mac and iPad only; the iPhone gets no shortcuts page, even with a hardware keyboard (owner, 2026-10-21).
