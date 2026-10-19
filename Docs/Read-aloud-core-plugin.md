# Read Aloud as a core plugin, off by default

Owner decision, 2026-10-19: Read Aloud is a core plugin, like Obsidian's core plugins (built in, listed in Settings › Core Plugins with a switch), and it is off by default.

## What exists today

Graphite already has core plugins. `CorePlugin` (`GraphitePreferences.swift`) lists 19 built-in features with a title, a summary and a symbol, and `readAloud` is one of them. Settings › Core Plugins shows a switch for each one. The state is kept on the device in `GraphiteDisabledCorePlugins`, the sorted raw values of the plugins that are turned off (`ST-04`), so every plugin is on until it is turned off. Views ask `preferences.isEnabled(_:)`. The community plugin host (`CommunityPluginHost`) is a separate system for Obsidian packages and is not changed here.

What is missing for Read Aloud:

1. Plugins can't be off by default: the store records only "turned off".
2. Read Aloud's settings page is listed under Options, not in the sidebar's Core Plugins section with Colors, Templates and the others (owner's screenshot, 2026-10-19).
3. The speech stack is built at every launch whatever the switch says. `WorkspaceModel` stores `let readAloud = ReadAloudVoices.makeController()`. That builds the neural voice library (manifest, voices folder, background download session, cache size task), the MLX passage renderer and its preparation queue (with two app-lifecycle observers), an `AVSpeechSynthesizer`, the Now Playing entry and the controller.
4. Five entry points are not gated:
   - The note editor's "Read from Here" edit-menu item and tap to read: `MarkdownPane.readAloudHooks` is passed unconditionally, so it starts reading with the plugin off.
   - The reader sheet (`GraphiteRootView`, bound to `readAloud.showsReader`) opens whatever the switch says.
   - "Play Next" and "Add to Listening Queue" appear in the file list's and the tabs' menus.
   - The PDF tab bar's Pencil tools always offer the Read Aloud pen (`TabBarPencilTools`, `offersReadAloudPen: true`).
   - Settings › General › Voice Credits builds the voice library whenever the page opens.

All the other entry points are gated already: the More › Read Aloud menus of notes and PDFs, the toolbar controls, the floating player, the PDF Read Aloud pen, PDF highlights, the Settings item and the `graphite://read` deep link. Graphite has no Read Aloud command in the command palette or menu bar, no Read Aloud keyboard shortcut and no App Intent, so nothing there needs hiding. If one is added later it has to check the switch too.

## The design

### Switch state

- `CorePlugin.isEnabledByDefault` is `false` for `readAloud` and `true` for every other plugin. It's an exhaustive `switch` with no `default:` (`FR-18`).
- `CorePluginSwitches` (a new value type in its own file) holds the two recorded sets and answers `isEnabled(_:)`.
  - `turnedOff` holds plugins that are on by default. It is stored in `GraphiteDisabledCorePlugins`, whose name and encoding stay unchanged (`ST-04`).
  - `turnedOn` holds plugins that are off by default. It is stored in a new key, `GraphiteEnabledCorePlugins`, with the same encoding: sorted raw values.
  - A plugin that is on by default is enabled unless it is in `turnedOff`. A plugin that is off by default is enabled only when it is in `turnedOn`.
- `GraphitePreferences.isEnabled` and `setEnabled` keep their signatures, so the 106 existing call sites don't change.
- `WorkspaceModel.setCorePluginEnabled(_:_:)` is the one intent the Settings switch calls. For Read Aloud it also builds the controller or ends it (see below).

### One-time migration, and the rule

**Rule:** a device that used Read Aloud before this change keeps it on. A new install starts with it off.

`CorePluginSwitchMigration` runs in `WorkspaceDeviceServices`, before the preferences are read, and only while `GraphiteEnabledCorePlugins` is absent. Once it has run, it writes the key, possibly as an empty list, so it never runs again and never turns Read Aloud back on after the person turns it off. It turns Read Aloud on when:

- Read Aloud was not turned off already (not in `GraphiteDisabledCorePlugins`), and
- the device shows earlier use. Either a preference whose name starts with `GraphiteReadAloud` or `readAloud` exists (the `ST-12` and `ST-14` keys: voice, speed, highlight, quality mode, remembered places, player corner and the others), or the voices folder (`Application Support/Voices`) holds a downloaded voice.

The decision is a pure function of those three facts and is tested with plain values (`FR-05`, `FR-98`). The folder check lists one small folder once per device, and only when no preference already answered. It is the one file read on the main actor this change adds, recorded here as an exception to `FR-103`. Hosted tests and package tests use their own preference suite and temporary folders, so they start as a new install would, with Read Aloud off.

Reading the key set never writes: `ReadAloudSession` only removes the abandoned keys of `ST-13`, which were already gone. None of the evidence keys is written at launch.

### Nothing loads while Read Aloud is off

- `WorkspaceModel.readAloud` becomes `private(set) var readAloud: ReadAloudController?`, and `readAloudNavigator` becomes `ReadAloudNavigator?`. Both are nil while the plugin is off.
- `WorkspaceDeviceServices` takes the Read Aloud factory as a dependency (`makeReadAloudController`). The live one is `ReadAloudVoices.makeController`; tests pass a counting one (`FR-46`, `FR-47`). With the plugin off, the workspace never calls the factory, so no voice library, MLX renderer, speech synthesizer or Now Playing entry exists. `ReadAloudVoices.library` and `preparation` are created on first access only. Their only other users are the Read Aloud settings page, which is hidden while the plugin is off, and the iOS background wake for voice downloads, which only happens after a download was started.
- Turning the plugin on builds the controller and the navigator right away, with no relaunch. Every gated view reads the optional, so it appears.
- Turning it off stops reading the way the player's Stop does: `clear()` stops the speech, releases the audio session and removes the Now Playing entry. It also closes the reader sheet, then drops the controller and the navigator. The process-wide voice library stays in memory until the app quits, because it is a `static let` today (`FR-48` finding `DIP-VOICE`, Phase 9). Its MLX model is freed when the preparation queue empties, as it is today.
- The ungated entry points get a gate: each of them reads the optional controller or navigator, so the editor hooks, the queue items, the tab bar's Read Aloud pen, the reader sheet and Voice Credits are absent while the plugin is off.

### Settings

- The Read Aloud page moves from Options to the sidebar's Core Plugins section, beside Colors and Templates, as `SettingsPage.plugin(.readAloud)`. It appears only while the plugin is on, like the other plugin pages. If the plugin is turned off while its page is open, the page falls back to Core Plugins.
- Settings › Core Plugins already lists Read Aloud with its switch, title and summary.

### Data kept

Turning Read Aloud off deletes nothing: downloaded voices, the prepared audio in `Caches/ReadAloudAudio`, the vault's `.graphite/pronunciations.json`, remembered places and every preference stay as they are. Turning it on again finds them.

Today, turning it off also asks "Delete Downloaded Voices?", with Keep Them as the default. That dialog is kept: it deletes only after the person confirms. **Owner decision (2026-10-19):** keep the offer when Read Aloud is turned off; it deletes only after confirmation.

## Per device or per vault

**Owner decision (2026-10-19): per device**, as implemented. The comparison that led to it:

| | Per device (today's store) | Per vault (Obsidian's way) |
| --- | --- | --- |
| Where | `GraphiteEnabledCorePlugins` and `GraphiteDisabledCorePlugins` in the device's preferences | `.obsidian/core-plugins.json` in the vault, or a Graphite file beside it |
| Matches Obsidian | No | Yes: Obsidian keeps its core plugin switches per vault |
| Read Aloud's resources | They are per device (voices take up to several GB in Application Support, and the player belongs to the window), so the switch matches what it controls | Switching vaults would build or end the speech stack. A vault with Read Aloud off would still hold voices on the device |
| Shared with Obsidian | Nothing written in the vault | Obsidian's `core-plugins.json` holds Obsidian's ids only. `read-aloud` isn't one, so it would need a Graphite-only entry or file, and Obsidian may drop unknown ids when it rewrites the file |
| Sync | Each device decides | iCloud or Obsidian Sync carries the choice to every device, including an iPhone that should not download voices |

Per device was recommended, for Read Aloud and the existing plugins: that is how the store already worked, and Read Aloud's cost (downloaded models, memory, the audio session) is a property of the device, not of the notes. Should per vault be wanted later, the change is contained: `CorePluginSwitches` would be read from a vault file by `OpenVault`, and the migration and gating stay as designed.

## Invariants and rules touched

- `ST-04`: `GraphiteDisabledCorePlugins` stays unchanged. The new key `GraphiteEnabledCorePlugins` is added beside it with the same encoding and pinned by the same test file.
- `ST-12`, `ST-13`, `ST-14`: the Read Aloud keys are read for the migration, never written or renamed.
- `RA-08`: the voices folder layout is read, never changed.
- `RA-19`, `RA-27`: turning the plugin off goes through `clear()`, which releases the audio session and the Now Playing entry, as Stop does.
- `ARCH-INV-07`: per-device core plugin state, unchanged scope.
- Rules: `FR-05` and `FR-98` (pure migration decision), `FR-18` (exhaustive default), `FR-46` and `FR-47` (factory injected at the composition root, no default argument), `FR-08` (no getter builds the controller), `FR-03` (the stored `readAloud` property changes type; no new feature-named property on `WorkspaceModel`), `FR-103` (the recorded one-time folder listing).

## Tests

- A fresh device has Read Aloud off, and every other plugin keeps its default.
- The migration keeps Read Aloud on when a Read Aloud preference exists, and when a downloaded voice exists. It keeps it off when Read Aloud was turned off before, and it runs only once: turned off after the migration, Read Aloud stays off at the next launch.
- No controller is made while the plugin is off: the counting factory is called 0 times. Turning the plugin on calls it once.
- Each entry point is hidden while the plugin is off and shown while it is on: the note's Read Aloud menu, the editor hooks, the PDF menu and pen, the floating player and toolbar controls, the reader sheet, the Settings page item and the deep link.
- Turning the plugin off during playback stops it: the session is idle, the reader sheet is closed, and the controller is gone.
- The hosted iPad tests that read aloud turn the plugin on first.
