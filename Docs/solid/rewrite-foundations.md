# Rewrite foundations: the design contract

Snapshot: b13dec3 (main, 2026-10-18).

This is the contract the cleanup is built against. It fixes the target module layout, the composition root, the ports, the replacement of every god object, state ownership, navigation, the feature template, the concurrency and error model, the rules new code is held to (`FR-01` to `FR-110`) and the migration plan (Phases 0 to 15). It is written from the twelve [area audits](areas/shell.md), the [architecture audit](cross-cutting/architecture.md), the six principle documents ([SRP](principles/single-responsibility.md), [OCP](principles/open-closed.md), [LSP](principles/liskov-substitution.md), [ISP](principles/interface-segregation.md), [DIP](principles/dependency-inversion.md), [clean code](principles/clean-code.md)), [testing.md](testing.md), [invariants.md](invariants.md), [defects.md](defects.md) and [findings-index.md](findings-index.md). `OBJECTIVE.md` and `RULES.md` stay authoritative; where this document is stricter than `RULES.md` it says so.

How to use it:

- Starting a wave: read section 12 for the phase, the area blueprint it names, the `FR` rules of section 11, and the invariant prefixes the phase must keep green.
- Reviewing a change: answer the checklist at the end of section 11.
- Adding a feature: section 9.
- Deciding where a type goes: sections 3, 5 and 6.

Conventions: "must" states a rule; a finding ID in backticks (`SRP-SHELL-01`) links to its area document by prefix; `FR-nn` is a rule of section 11; `T-nn` is an item of the [testing migration backlog](testing.md); `<AREA>-INV-nn` and the row codes `ST-nn`, `D-nn`, `LK-nn` are rows of [invariants.md](invariants.md). Every name proposed here follows `RULES.md`: full words, no invented abbreviations, a protocol only where a second implementation or a stated test or isolation need exists, no forwarding layers.

## 1. What the audit says has to be fixed

The audit holds 501 findings and bug reports: 75 SRP, 52 OCP, 58 LSP, 40 ISP, 52 DIP, 151 clean code, 73 BUG, of which 33 findings are High ([findings-index.md](findings-index.md)). Verification reduced the 73 bug reports plus 4 found by the verifiers and 1 by the lead to 76 distinct defects: 5 High and 33 Confirmed Medium reach users today ([defects.md](defects.md), "Fix before the cleanup starts"). The findings fall into the clusters below. A cluster is listed High when it contains a High finding, then "High by defect" when its defects are High, then Medium and Low. The section that carries the target is named in each entry.

### 1.1 High clusters

**C-01 An application-wide aggregate with no composition root and no vault lifetime**
- Findings: `SRP-ARCH-01`, `SRP-SHELL-01`, `SRP-SHELL-02`, `DIP-ARCH-01`, `DIP-SHELL-01`, `ISP-ARCH-01`, `ISP-SHELL-01`, `SRP-ARCH-05`, `SRP-ARCH-04`, `SRP-SHELL-04`, `OCP-ARCH-03`, `OCP-SHELL-06`, `OCP-CANVAS-03`, `ISP-SHELL-02`, `ISP-SHELL-03`, `ISP-PLUGIN-01`; defects `BUG-ARCH-03`, `BUG-ARCH-06`.
- Cost: `WorkspaceModel` has 86 stored properties and builds 13 collaborators in property initialisers, so no test can isolate it and the vault switch resets about 25 fields by hand, missing nine; 74 declarations take the whole model to use a few members.
- Target: `AppEnvironment` built once in the app target; `WorkspaceModel` becomes a router that holds `OpenVault?`, `TabWorkspace` and the narrow models of section 6; vault duties are opt-in by conformance (sections 4, 6, `FR-02`, `FR-04`, `FR-46`).

**C-02 Persisted device state has no owner and `UserDefaults` is a message bus**
- Findings: `DIP-ARCH-03`, `DIP-ARCH-04`, `DIP-SHELL-02`, `DIP-SHELL-03`, `DIP-CANVAS-01`, `DIP-INK-03`, `DIP-READING-03`, `DIP-PLUGIN-01`, `DIP-VOICE-02`, `CC-VOICE-05`, `CC-INK-09`, `CC-CANVAS-08`, `SRP-SHELL-06`; defects `BUG-ARCH-06`, `BUG-ARCH-07`.
- Cost: about 91 key names in about 25 files under four naming schemes, so removing a vault forgets only the keys someone remembered and Read Aloud places leak between vaults.
- Target: a `DeviceStateKey` registry and one `DeviceStateStore` over an injected `UserDefaults` (section 7, `FR-73`, `FR-74`).

**C-03 Per-feature god objects that mix platform callbacks, state, I/O and rules**
- Findings: `SRP-EDITOR-01`, `SRP-LECTURE-01`, `SRP-LECTURE-02`, `SRP-PLUGIN-01`, `SRP-CANVAS-01`, `SRP-INK-01`, `SRP-VOICE-01`, `SRP-VOICE-02`, `SRP-READING-01`, `SRP-BASES-01`, `SRP-BASES-02`, `SRP-INK-02`, `SRP-INK-03`, `SRP-INK-04`, `SRP-LECTURE-03`, `SRP-EDITOR-02`, `SRP-VAULT-01`, `SRP-VAULT-02`, `SRP-VOICE-03`, `SRP-VOICE-04`, `SRP-VOICE-05`.
- Cost: the iPad editor coordinator has 47 stored properties and 16 kinds of work, `PDFAnnotationCoordinator` 37 and 13, `CanvasSession` 34, `CommunityPluginHost` 63, `ReadAloudController` 39, `HistoryCanvasView` 35 plus 2 static; none can be tested without a window or a vault.
- Target: the replacement types of section 6, each with one responsibility and a test that constructs it with plain values (`FR-01`, `FR-05`, `FR-06`, `FR-96`).

**C-04 One rule with several implementations that already disagree**
- Findings: `SRP-BASES-03`, `LSP-ARCH-01`, `LSP-ARCH-02`, `LSP-BASES-01`, `LSP-MDCORE-01`, `LSP-READING-01`, `LSP-READING-03`, `LSP-READING-04`, `LSP-VAULT-01`, `LSP-VAULT-03`, `LSP-LECTURE-01`, `LSP-SHELL-01`, `LSP-EDITOR-05`, `LSP-INK-03`, `SRP-READING-06`, `CC-ARCH-08`, `CC-ARCH-10`, `CC-VAULT-03`, `CC-BASES-04`, `CC-INK-04`, `CC-LECTURE-03`, `CC-SHELL-05`; defects `BUG-VAULT-01`, `BUG-BASES-03`, `BUG-READING-01`, `BUG-READING-02`, `BUG-READING-03`, `BUG-MDCORE-02`, `BUG-MDCORE-04`, `BUG-ARCH-01`, `BUG-ARCH-05`.
- Cost: link resolution has five implementations, two media vocabularies disagree about which files are audio, the same Markdown line gets different answers from parallel scanners, and fold keys differ between reading view and editor; each disagreement is a shipped defect.
- Target: one owner per rule in Core with a corpus parity test and a contract suite (section 5, Phase 3, `FR-10`, `FR-87`).

**C-05 Platform variants of one name honour different contracts**
- Findings: `LSP-EDITOR-01`, `LSP-EDITOR-02`, `LSP-EDITOR-03`, `LSP-EDITOR-06`, `LSP-LECTURE-02`, `LSP-CANVAS-02`, `LSP-SHELL-03`, `LSP-VOICE-06`, `CC-EDITOR-04`; defects `BUG-EDITOR-01`, `BUG-EDITOR-02`, `BUG-EDITOR-03`, `BUG-EDITOR-04`, `BUG-CANVAS-03`.
- Cost: the Mac editor serves six session duties less than the iPad editor, about 14 iPad and Mac function pairs repeat the same logic, and the Mac `GraphitePDFView` ignores 10 of 15 inputs.
- Target: shared decisions live in shared types, platform files hold only platform calls, and one contract suite runs on both coordinators (`FR-06`, `FR-26`, `FR-87`, owner question 2).

**C-06 The plugin boundary is an untyped 83-operation protocol over a global namespace with a boolean lifecycle**
- Findings: `OCP-PLUGIN-01`, `OCP-RUNTIME-01`, `SRP-RUNTIME-02`, `LSP-PLUGIN-01`, `CC-PLUGIN-01`, `ISP-PLUGIN-03`, `ISP-RUNTIME-01`, `ISP-PLUGIN-02`, `OCP-RUNTIME-03`, `SRP-RUNTIME-01`, `SRP-PLUGIN-02`, `DIP-RUNTIME-01`, `LSP-RUNTIME-01`, `LSP-RUNTIME-02`, `CC-PLUGIN-04`, `CC-PLUGIN-05`; defects `BUG-PLUGIN-01`, `BUG-PLUGIN-02`, `BUG-PLUGIN-03`, `BUG-PLUGIN-06`, `BUG-RUNTIME-01`.
- Cost: 83 operation names are kept in step by hand in three places, an unknown operation succeeds, the Node test host accepts edits that production refuses (which hides `BUG-RUNTIME-01`), and the runtime lifecycle is booleans (which causes `BUG-PLUGIN-01`).
- Target: one typed message schema generating Swift and JavaScript, a `CommunityPluginSession` with a phase enum, and a Node host that runs the production fixture (section 5, 9, 10, Phase 9, `FR-16`, `FR-21`, `FR-22`, `FR-88`).

**C-07 Adapters of one Read Aloud port honour different contracts**
- Findings: `LSP-VOICE-01`, `ISP-VOICE-01`, `LSP-VOICE-02`, `LSP-VOICE-03`, `CC-VOICE-07`, `ISP-VOICE-02`; defects `BUG-VOICE-01`, `BUG-VOICE-03`, `BUG-VOICE-04`, `BUG-VOICE-05`, `BUG-VOICE-08`.
- Cost: the system-voice and neural adapters differ on speed range, word timing and stop semantics; `ReadAloudSpeaking` has 16 requirements over 6 concerns, four functions named `stop` have four scopes, and six private test fakes run through defaults that drop request fields.
- Target: `ReadAloudSpeechPlayback` with capabilities reported as values, `ReadAloudTransport.stop(scope:)` and one contract suite (section 5, Phase 8, `FR-30`, `FR-33`, `FR-87`).

**C-08 A new kind of document, panel or command is wired by hand at many sites**
- Findings: `OCP-SHELL-01`, `OCP-ARCH-01`, `OCP-ARCH-02`, `OCP-SHELL-02`, `OCP-SHELL-03`, `OCP-SHELL-05`, `OCP-BASES-02`, `OCP-CANVAS-01`, `OCP-EDITOR-01`, `OCP-EDITOR-02`, `OCP-INK-01`, `OCP-INK-02`, `OCP-INK-03`, `OCP-LECTURE-02`, `OCP-LECTURE-04`, `OCP-READING-01`, `OCP-READING-05`, `OCP-VOICE-01`, `OCP-PLUGIN-02`, `OCP-MDCORE-03`.
- Cost: a new document kind touches 13 UI files and 16 places in 14 files, three of them behind `default:`; 27 commands are declared twice; what can be created is listed seven times.
- Target: one enum case plus one descriptor registered by the owning module, and every list derived from the table (sections 8, 9, `FR-17`, `FR-18`, `FR-23`).

**C-09 Singletons and mutable statics carry process-wide state**
- Findings: `DIP-INK-01`, `DIP-ARCH-02`, `DIP-INK-02`, `DIP-SHELL-04`, `DIP-EDITOR-01`, `DIP-READING-02`, `DIP-READING-04`, `DIP-CANVAS-02`, `DIP-LECTURE-01`, `DIP-VOICE-01`, `DIP-VOICE-03`, `DIP-MDCORE-01`, `CC-INK-06`, `CC-PLUGIN-14`, `CC-VOICE-14`.
- Cost: 11 `static let shared` singletons, 2 static service lets and 24 stored mutable statics (`PencilToolbox.shared` is read in five files even where an instance is passed in) make correctness depend on one workspace per process, which tests already break.
- Target: every one becomes an instance owned by `AppEnvironment` or a feature model, with the fate listed in section 4 (`FR-48`, `FR-49`, `FR-72`).

**C-10 The test suite has no shared support, no CI and is not hermetic**
- Findings: `CC-ARCH-09`, `CC-SHELL-09`, `CC-INK-15`, `CC-LECTURE-10`, `CC-VAULT-10`, `CC-BASES-10`, `CC-MDCORE-06`, `CC-EDITOR-11`, `CC-READING-10`, `CC-RUNTIME-05`, `LSP-ARCH-03`, `LSP-VAULT-02`, `LSP-VOICE-02`, `LSP-LECTURE-03`, `LSP-EDITOR-04`, `LSP-MDCORE-03`, `DIP-INK-06`, `DIP-VOICE-05`.
- Cost: 39 `waitUntil` copies, 101 `UserDefaults.standard` uses and 261 sleeps in tests, 31 files named after audit rounds, the only named fake succeeds where production fails, and no workflow file exists ([testing.md](testing.md) sections 1 and 2).
- Target: `GraphiteTestSupport`, contract suites, an injected clock, hosted launch mode and CI on every push (Phase 1, `FR-83` to `FR-100`).

### 1.2 Clusters with High defects

**C-11 Failures become silence, empty results or defaults**
- Findings: `CC-ARCH-02`, `CC-SHELL-04`, `CC-CANVAS-07`, `CC-LECTURE-14`, `CC-READING-04`, `CC-EDITOR-09`, `CC-VOICE-11`, `CC-RUNTIME-06`, `CC-VAULT-01`, `CC-INK-07`, `LSP-SHELL-02`, `LSP-CANVAS-01`, `LSP-LECTURE-05`, `LSP-PLUGIN-02`, `LSP-PLUGIN-03`, `LSP-BASES-02`, `LSP-INK-01`; defects `BUG-SHELL-03`, `BUG-VOICE-V01`, `BUG-VAULT-02`, `BUG-PLUGIN-05`, `BUG-ARCH-04`.
- Cost: 20 of 63 sampled `try?` sites hide a failure the person needs to see; quitting on the Mac discards unsaved edits after a swallowed save failure and a failed pronunciation read is overwritten by the next add.
- Target: reads return `missing`, `contents` or `unreadable`, destructive steps stop when the safety copy fails, and writes report failure (`FR-58` to `FR-61`, Phase 0 fixes, Phase 4 structure).

**C-12 Parser bounds and constant patterns are decided per call site**
- Findings: `CC-MDCORE-09`, `CC-MDCORE-01`, `CC-BASES-03`, `CC-RUNTIME-12`, `CC-LECTURE-09`; defects `BUG-MDCORE-01`, `BUG-MDCORE-05`.
- Cost: `Document(parsing:)` appears at 5 sites and one of them skips the nesting guard, which terminates the app on a deeply nested note while a post-processing plugin runs; 53 constant patterns fail silently.
- Target: `BoundedMarkdownParser` as the only parser entry and one `StaticPattern` helper (`FR-62`, `FR-68`).

### 1.3 Medium clusters

**C-13 Errors are English sentences and nothing words them in one place**
- Findings: `CC-ARCH-01`, `CC-VAULT-02`, `CC-VAULT-06`, `CC-PLUGIN-05`, `CC-RUNTIME-05`, `CC-INK-08`, `CC-BASES-07`, `CC-CANVAS-03`, `CC-VOICE-10`, `CC-LECTURE-04`, `CC-SHELL-06`, `CC-READING-05`, `DIP-MDCORE-02`, `DIP-PLUGIN-03`, `SRP-SHELL-03`, `ISP-BASES-02`.
- Cost: 84 `GraphiteError` constructions in Core carry prose, code branches on message suffixes, 208 `localizedDescription` uses reach the person, and 80 operations share one `errorMessage` slot.
- Target: typed errors with facts, one `ErrorPresenter` and a string catalogue (section 10, `FR-55`, `FR-63`, `FR-64`).

**C-14 Time orders work, tasks have no owner and "latest answer wins" is hand-written**
- Findings: `CC-ARCH-03`, `CC-ARCH-04`, `CC-ARCH-05`, `CC-SHELL-02`, `CC-SHELL-03`, `CC-READING-02`, `CC-READING-06`, `CC-VOICE-02`, `CC-VOICE-03`, `CC-PLUGIN-02`, `CC-PLUGIN-03`, `CC-RUNTIME-03`, `CC-INK-03`, `CC-INK-14`, `CC-CANVAS-02`, `CC-EDITOR-02`, `CC-LECTURE-05`, `CC-BASES-02`, `DIP-SHELL-05`, `DIP-EDITOR-03`, `DIP-INK-05`, `DIP-LECTURE-04`, `DIP-CANVAS-04`, `DIP-VOICE-04`, `DIP-VAULT-01`, `DIP-BASES-02`, `DIP-MDCORE-03`, `DIP-RUNTIME-02`.
- Cost: 51 sleeps and 10 `asyncAfter` stand in for completion signals, about 13 debounce or "latest wins" copies exist, and the clock is read inline in logic so no test can advance it.
- Target: an injected `ApplicationClock`, three tested primitives (`Debouncer`, `LatestRequest`, `withTimeout`) and task ownership (section 10, `FR-50`, `FR-65` to `FR-67`).

**C-15 Multi-state flows are boolean sets and outcomes ride on shared mutable fields**
- Findings: `SRP-VAULT-03`, `SRP-MDCORE-02`, `SRP-RUNTIME-04`, `SRP-RUNTIME-06`, `SRP-INK-03`, `OCP-INK-02`, `CC-EDITOR-03`, `CC-LECTURE-07`, `CC-LECTURE-13`, `CC-VOICE-12`, `CC-CANVAS-01`, `CC-INK-01`, `CC-INK-02`, `ISP-CANVAS-02`, `ISP-LECTURE-04`, `ISP-BASES-02`, `ISP-PLUGIN-02`; defects `BUG-INK-03`, `BUG-LECTURE-01`, `BUG-CANVAS-01`.
- Cost: seven re-entrancy booleans in the editor, twelve presentation booleans, a drag enum plus four loose fields, and views that write session fields directly cause double rotation, double saves and lost typed text.
- Target: enums changed by intent methods, `private(set)` state and returned outcomes (`FR-11`, `FR-12`, `FR-40`).

**C-16 Views do I/O, decide rules, and `body` or getters write state**
- Findings: `SRP-SHELL-05`, `SRP-CANVAS-03`, `SRP-CANVAS-05`, `SRP-EDITOR-05`, `SRP-INK-05`, `SRP-LECTURE-04`, `SRP-LECTURE-05`, `SRP-READING-03`, `SRP-READING-05`, `SRP-READING-07`, `SRP-PLUGIN-03`, `CC-LECTURE-06`, `CC-READING-03`, `CC-VOICE-04`, `CC-BASES-06`, `CC-EDITOR-08`, `DIP-BASES-01`, `DIP-READING-01`, `DIP-EDITOR-02`, `DIP-CANVAS-03`, `DIP-LECTURE-02`.
- Cost: 34 `FileManager.default` uses sit in `GraphiteUI`, autosave lives in invisible background views, and install flows run inside settings views, so none of it is testable or cancellable by an owner.
- Target: each UI event calls one model method that returns a typed result; autosave and release are owned by models (`FR-07`, `FR-08`, `FR-09`, `FR-51`).

**C-17 Module boundaries do not exist: `GraphiteUI` holds every feature, Core holds I/O, value types sit in adapters**
- Findings: `SRP-ARCH-02`, `SRP-ARCH-03`, `DIP-ARCH-05`, `DIP-MDCORE-04`, `DIP-CANVAS-03`, `SRP-READING-08`, `SRP-PLUGIN-04`, `ISP-VAULT-01`, `ISP-BASES-01`, `ISP-EDITOR-01`, `ISP-CANVAS-04`, `ISP-VAULT-02`, `DIP-VAULT-02`.
- Cost: 153 files of one module, nine `GraphiteCore` files that touch `FileManager`, `URLSession` or the keychain, and consumers that receive all 32 `VaultStore` methods to use four or five.
- Target: the layout of section 3 with direction enforced by `Package.swift` (`FR-38`, `FR-39`, `FR-54`).

**C-18 Vocabularies shared with scripts and files are strings, and `default:` hides new cases**
- Findings: `OCP-BASES-01`, `OCP-BASES-03`, `OCP-LECTURE-01`, `OCP-LECTURE-03`, `OCP-MDCORE-02`, `OCP-INK-04`, `OCP-READING-04`, `OCP-VAULT-01`, `OCP-VAULT-02`, `OCP-VAULT-03`, `OCP-SHELL-07`, `OCP-CANVAS-02`, `OCP-VOICE-02`, `OCP-PLUGIN-03`, `OCP-READING-02`, `ISP-ARCH-02`, `ISP-LECTURE-03`, `ISP-VAULT-03`, `ISP-MDCORE-02`, `ISP-VOICE-03`, `LSP-BASES-03`.
- Cost: 132 untyped-dictionary or `Any` sites (ISP 13) cross boundaries, bookmark kinds are compared as strings in 9 places, and settings files are written by four different JSON writers (one narrower than its reader, which strips hand-written IPA, `BUG-VOICE-10`).
- Target: `unknown(raw)` enums at the boundary, `Codable` types for read and write, and generated shared vocabularies (`FR-20`, `FR-21`, `FR-44`).

**C-19 Hot paths cost the collection, not the change**
- Findings: `CC-INK-05`, `CC-VOICE-13`, `CC-VOICE-14`, `CC-PLUGIN-06`, `CC-PLUGIN-13`, `CC-CANVAS-09`, `CC-RUNTIME-11`, `CC-MDCORE-02`, `DIP-INK-03`.
- Cost: zooming a selection rebuilds its whole menu and reads stored colours on every layout pass, every plugin message is validated and re-serialised on the main actor, and every create, delete or rename re-resolves every link in the plugin runtime.
- Target: work proportional to the change and off the main actor (`FR-69`, `FR-75`).

**C-20 Runtime JavaScript is a handful of closures that mutate each other's objects**
- Findings: `SRP-RUNTIME-01`, `SRP-RUNTIME-03`, `SRP-RUNTIME-05`, `OCP-RUNTIME-02`, `OCP-RUNTIME-03`, `DIP-RUNTIME-01`, `DIP-RUNTIME-03`, `ISP-RUNTIME-02`, `CC-RUNTIME-02`, `CC-RUNTIME-09`, `CC-RUNTIME-01`.
- Cost: `plugins.js` is one 1324-code-line closure with about 18 responsibilities, nine fields are written onto objects from files that do not own them, and one platform prototype is patched for the whole page.
- Target: one object per file, registration through `HostMessageRouter`, a scoped `listener-marking.js` (`FR-16`, `FR-25`, `FR-57`).

### 1.4 Low clusters

**C-21 Identity and equality do not mean "the same thing"**
- Findings: `LSP-VAULT-04`, `LSP-CANVAS-03`, `LSP-LECTURE-04`, `LSP-READING-02`, `LSP-READING-05`, `LSP-READING-06`, `LSP-SHELL-04`, `OCP-VOICE-02`, `CC-EDITOR-10`; defects `BUG-READING-01`, `BUG-READING-02`.
- Cost: a bookmark's identity is read back from its display label, block identity is positional, and one identity changes on rename.
- Target: identities computed from structured content (`FR-27`, `FR-28`).

**C-22 Long functions, multi-concept files, literal constants, history-narrating comments, dead code and loose names**
- Findings: `CC-SHELL-01`, `CC-EDITOR-01`, `CC-READING-01`, `CC-MDCORE-03`, `CC-VAULT-05`, `CC-BASES-01`, `CC-CANVAS-04`, `CC-INK-12`, `CC-LECTURE-02`, `CC-VOICE-01`, `CC-PLUGIN-11`, `CC-RUNTIME-01`, `SRP-READING-02`, `SRP-MDCORE-04`, `SRP-INK-06`, `SRP-VAULT-04`, `SRP-LECTURE-06`, `SRP-PLUGIN-05`, `CC-SHELL-07`, `CC-EDITOR-05`, `CC-CANVAS-05`, `CC-INK-10`, `CC-EDITOR-06`, `CC-INK-11`, `CC-VOICE-09`, `CC-ARCH-07`, `CC-INK-13`, `CC-LECTURE-11`, `CC-VOICE-06`, `CC-VAULT-07`, `CC-VOICE-15`, `CC-PLUGIN-12`.
- Cost: 29 functions over 40 code lines in SHELL alone and 19 in LECTURE, a 64-type library file that other areas import, 35 dated comments and 14 that name the owner.
- Target: the size register becomes a gate, files are split by responsibility, constants are named with units and comments state rules (`FR-76` to `FR-82`).

## 2. What must be carried over unchanged

The tables list every "What to keep" row of the twelve area audits and the architecture audit (290 rows). The cleanup moves each item intact to its new home, then splits it; it never rewrites one from scratch. A move is a commit that changes no behaviour and keeps the test that pins the item green. Each row gives the first evidence link; the full list of links and the reasoning are in section 6 of the named audit. Where a row cites a finding in the area, the finding says what changes around the item.

### 2.1 SHELL (18 rows; full evidence in [SHELL](areas/shell.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Derived tab state is projected from `layout` and written only when it changes | Views that show only the focused file are not redrawn on each frame of a divider drag. | [WorkspaceModel.swift:40-52](../../Sources/GraphiteUI/WorkspaceModel.swift#L40-L52) |
| `TabLayout` is a Core value type; the model only adds documents | Tab rules are unit-testable without UI (`TabLayoutTests`). | [WorkspaceTabs.swift:84-216](../../Sources/GraphiteUI/WorkspaceTabs.swift#L84-L216) |
| Pure, tested decision helpers | These are "decide, then do" already in place. | [WorkspaceModel.swift:1405-1453](../../Sources/GraphiteUI/WorkspaceModel.swift#L1405-L1453) |
| A stale result never lands in a newer state | Each async step re-checks that it still belongs to the current vault or request. | [WorkspaceModel.swift:523-556](../../Sources/GraphiteUI/WorkspaceModel.swift#L523-L556) |
| Typed text is never lost on navigation, close, move or switch | This is the OBJECTIVE.md contract ("never discard unsaved user work"), made concrete. | [WorkspaceTabs.swift:226-239](../../Sources/GraphiteUI/WorkspaceTabs.swift#L226-L239) |
| Embeds are refused, not forced, after slow writes | The file is kept and the person is told, instead of overwriting their text or inserting into a conflicted note. | [WorkspaceModel.swift:875-891](../../Sources/GraphiteUI/WorkspaceModel.swift#L875-L891) |
| Moves are asked about one at a time and queued | Links are never silently left broken, and a multi-item drop does not stack dialogs. | [WorkspaceFileManagement.swift:6-30](../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L6-L30) |
| Conflict-version feature structure | Already the target shape: a feature model, a seam with a test double, bounded background work, and refusal on a stale listing. | [ConflictVersionsSheet.swift:8-65](../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L8-L65) |
| Tolerant persisted list | "Unreadable data is moved aside, never overwritten" is already implemented. | [VaultLibrary.swift:67-109](../../Sources/GraphiteUI/VaultLibrary.swift#L67-L109) |
| `DocumentPlaceStore`: read once, write on change, injected defaults | This is the pattern `VaultDeviceMemory` should generalise to the other four per-vault key families. | [WorkspacePlaces.swift:79-112](../../Sources/GraphiteUI/WorkspacePlaces.swift#L79-L112) |
| Places taken synchronously when the scene goes inactive | The reason is in the comment: by the time a save task runs, iPadOS can have resized the window. | [GraphiteRootView.swift:228-231](../../Sources/GraphiteUI/GraphiteRootView.swift#L228-L231) |
| Settings writes serialised, each building on the last | Quick taps are not lost, and Obsidian's concurrent edits to `app.json` survive. | [SettingsView.swift:960-986](../../Sources/GraphiteUI/SettingsView.swift#L960-L986) |
| Large-vault file tree performance | Measured fixes for vaults of about 25,000 files at the root. | [VaultSidebar.swift:572-645](../../Sources/GraphiteUI/VaultSidebar.swift#L572-L645) |
| Mac quit answers once | Correct once-only primitive. | [GraphiteMacScenes.swift:66-77](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L66-L77) |
| Mac single window | Two workspaces on one index file would fail each other's writes. | [GraphiteMacScenes.swift:23-28](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L23-L28) |
| Passive touch observer and presented-screen observer | Both observe without competing with the editor's or PencilKit's gestures, and `isolated deinit` stops the observer. | [WorkspacePanes.swift:751-813](../../Sources/GraphiteUI/WorkspacePanes.swift#L751-L813) |
| Palette closes before it acts | A command that opens another palette is not undone by the close. | [QuickPalette.swift:193-196](../../Sources/GraphiteUI/QuickPalette.swift#L193-L196) |
| `WorkspaceFocusMode` value type | Already a small, tested state machine. | [WorkspaceFocusMode.swift:4-23](../../Sources/GraphiteUI/WorkspaceFocusMode.swift#L4-L23) |

### 2.2 EDITOR (21 rows; full evidence in [EDITOR](areas/editor.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Styling changes attributes only; the text is never rewritten by styling | Saving writes exactly what was typed; undo stays exact (OBJECTIVE: notes are not rewritten by opening them). | [MarkdownTextStyler.swift:188-189](../../Sources/GraphiteUI/MarkdownTextStyler.swift#L188-L189) |
| Edit tracking from `NSTextStorage.didProcessEditing`, before any selection callback | Catches every edit path (typing, undo, find and replace, insertions) and lets every consumer ask "do my caches describe the text?" instead of guessing. | [MarkdownEditorStyling.swift:124-145](../../Sources/GraphiteUI/MarkdownEditorStyling.swift#L124-L145) |
| Pure range-mapping types with three explicit policies (covering, insertion target, replaced range) | Asynchronous results (pastes, completions) are moved past later typing, or refused when typing touched their range, instead of corrupting the note. | [LivePreviewEditTracking.swift:40-74](../../Sources/GraphiteUI/LivePreviewEditTracking.swift#L40-L74) |
| Narrow ports where substitution is real: `MarkdownStyledTextView` (5 members) and `RetainableMarkdownEditor` (3 members) | Two production implementations each, plus a test fake for retention (`MarkdownEditorRetentionTests.swift:8-19`); exactly the protocol use RULES.md allows. | [MarkdownEditorStyling.swift:12-22](../../Sources/GraphiteUI/MarkdownEditorStyling.swift#L12-L22) |
| Undo-preserving edit paths: minimal diff on composed-character boundaries, own inverse when the iPad view has no keyboard | External edits and block edits join the note's history; the undo handler holds its own token so it never resurrects a discarded editor. | [LivePreviewEditTracking.swift:766-787](../../Sources/GraphiteUI/LivePreviewEditTracking.swift#L766-L787) |
| Insertions queued in the session and applied through the editor, flushed into the text when the editor detaches or before a save | No requested insertion is lost or applied twice; queued work counts as unsaved. | [MarkdownSession.swift:318-338](../../Sources/GraphiteUI/MarkdownSession.swift#L318-L338) |
| Save serialization and conflict detection by revision; BOM kept apart and written back | Never overwrites an external edit silently; bytes the person did not edit stay identical. | [MarkdownSession.swift:142-175](../../Sources/GraphiteUI/MarkdownSession.swift#L142-L175) |
| Revealed-markup delta restyle with block-context checkpoints | Cursor movement in a long note restyles only markers that change; checkpoints are invalidated by the storage's own edit notification. | [MarkdownTextStyler.swift:417-470](../../Sources/GraphiteUI/MarkdownTextStyler.swift#L417-L470) |
| Rendered-block placement only on fragments TextKit laid out for the viewport | Avoids forcing layout of off-screen text, which moved the visible text under the views. | [LivePreviewRenderedBlocks.swift:356-405](../../Sources/GraphiteUI/LivePreviewRenderedBlocks.swift#L356-L405) |
| Bounded, LRU-like caches with cost estimates: detached views, measured heights, recent spans, math images | Memory stays bounded; players are never kept so audio cannot play off screen (LivePreviewRenderedBlocks.swift:743-746). | [LivePreviewRenderedBlocks.swift:700-793](../../Sources/GraphiteUI/LivePreviewRenderedBlocks.swift#L700-L793) |
| The layout fragment decides its drawing needs once, at creation | Most paragraphs draw with no extra contexts; correct because TextKit makes a new fragment when attributes change. | [ConcealedReplacementLayoutFragment.swift:27-79](../../Sources/GraphiteUI/ConcealedReplacementLayoutFragment.swift#L27-L79) |
| Retention policy is a small, separately tested object | Bounded by count and UTF-16 length; stale editors (tab shows another file) are discarded. | [MarkdownEditorRetention.swift:28-142](../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L28-L142) |
| `EditorContainersInUse` handles SwiftUI's make-before-dismantle order | Fixes a real re-entrancy hang without moving the first responder inside a SwiftUI update. | [MarkdownEditorRetention.swift:144-173](../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L144-L173) |
| Focus policy: the note starts editing only when touched or asked | Prevents SwiftUI's focus system from raising the keyboard or stealing tabs; rendered blocks keep their own gestures. | [NativeMarkdownEditor.swift:65-113](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L65-L113) |
| Pure editing helpers return one `MarkdownTextEdit` | Decide-then-do: the decision is a value, the editor performs it through undo. | [EditorKeyboardToolbar.swift:76-110](../../Sources/GraphiteUI/EditorKeyboardToolbar.swift#L76-L110) |
| Platform-neutral context-menu model rendered by UIKit and AppKit builders | One list of items for both platforms; the model is tested on the Mac (`UiEditorMacContextMenuTests`). | [EditorContextMenu.swift:35-59](../../Sources/GraphiteUI/EditorContextMenu.swift#L35-L59) |
| Table cell editing: debounced draft, owned commit task, own undo manager per cell | The task has an owner that cancels it; typing undone after a move cannot apply to another cell. | [LivePreviewTableEditing.swift:122-142](../../Sources/GraphiteUI/LivePreviewTableEditing.swift#L122-L142) |
| Quick font size never takes Apple Pencil or a view that zooms itself | Protects the Pencil-first priority; the policy is a pure static function. | [QuickFontSizeGestures.swift:40-58](../../Sources/GraphiteUI/QuickFontSizeGestures.swift#L40-L58) |
| `UndoAvailability` follows one undo manager, assigns only on change | Observation stays cheap; the toolbar is right for notes and PDFs alike. | [UndoAvailability.swift:32-95](../../Sources/GraphiteUI/UndoAvailability.swift#L32-L95) |
| Smart dashes and quotes off in the note and in cells | `---` and quotes are Markdown syntax; substitution would corrupt notes. | [NativeMarkdownEditor.swift:620-621](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L620-L621) |
| Comments that state a platform constraint precisely | These are the invariants a refactor must keep; strip only the incident narration (CC-EDITOR-06). | [NativeMarkdownEditor.swift:1089-1092](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L1089-L1092) |

### 2.3 READING (23 rows; full evidence in [READING](areas/reading.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Task ticks land only where the task still is | A tap on an out-of-date drawing changes nothing instead of another task. | [MarkdownPreview.swift:392-396](../../Sources/GraphiteUI/MarkdownPreview.swift#L392-L396) |
| Closed-file writes keep revision and byte-order mark | Never overwrites an external edit; bytes the user did not change stay (OBJECTIVE.md "never silently overwrite"). | [WorkspaceMentions.swift:75-82](../../Sources/GraphiteUI/WorkspaceMentions.swift#L75-L82) |
| Property rename reports what it could not do | Partial success is visible and nothing is half-renamed silently. | [WorkspaceTagsAndProperties.swift:58-102](../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L58-L102) |
| A mention is re-checked before linking | Prevents writing a link into the wrong words or the wrong note. | [WorkspaceMentions.swift:91-97](../../Sources/GraphiteUI/WorkspaceMentions.swift#L91-L97) |
| Read Aloud word updates are confined | Measured: under 1 ms per word on a 0.8 MB note (`Architecture.md:307`). | [MarkdownPreview.swift:1058-1078](../../Sources/GraphiteUI/MarkdownPreview.swift#L1058-L1078) |
| Build request compared, not hashed; blocks view compared by value and not `.equatable()` | Hashing the note at every update stalled the main thread; `.equatable()` made the lazy stack build every block. | [MarkdownPreview.swift:1192-1243](../../Sources/GraphiteUI/MarkdownPreview.swift#L1192-L1243) |
| Build cache per session | Switching from writing to reading shows the note at once; pinned by `testBuildKeyDescribesOnlyAnEqualBuild` (UiReadingViewTests.swift:283). | [MarkdownSession.swift:115](../../Sources/GraphiteUI/MarkdownSession.swift#L115) |
| Reading place as a note offset | The note keeps its place across view switches and relaunch; pinned by `testTheReadingViewKnowsWhichCharacterOfTheNoteIsAtItsTop` (UiReadingViewTests.swift:464). | [MarkdownPreview.swift:697-731](../../Sources/GraphiteUI/MarkdownPreview.swift#L697-L731) |
| One vocabulary for Graphite's private links and image fragments | Encoder and decoder live together; tests pin unbalanced parentheses and trailing backslashes (UiReadingViewTests.swift:128-140). | [MarkdownPreview.swift:125-195](../../Sources/GraphiteUI/MarkdownPreview.swift#L125-L195) |
| A note's private-use characters survive the marker rewrite | Icon-font glyphs are neither turned into checkboxes nor lost. | [MarkdownPreview.swift:201-230](../../Sources/GraphiteUI/MarkdownPreview.swift#L201-L230) |
| Vault boundary for images and file links | A crafted Markdown image cannot read outside the vault. | [MarkdownPreview.swift:2565-2570](../../Sources/GraphiteUI/MarkdownPreview.swift#L2565-L2570) |
| Thumbnail cache with honest invalidation | Bounded memory, no stale drawings after a save; tested (UiReadingViewTests.swift:339, UiEmbeddedImageDecodingTests.swift:54-62). | [MarkdownPreview.swift:2645-2706](../../Sources/GraphiteUI/MarkdownPreview.swift#L2645-L2706) |
| Media players outlive lazy rows and stop with their embeds | A lecture recording keeps playing while the user scrolls, and never plays on unseen; tested (UiReadingViewTests.swift:235). | [MarkdownPreview.swift:2722-2751](../../Sources/GraphiteUI/MarkdownPreview.swift#L2722-L2751) |
| Pure, injected property parsing | Refuses ambiguous numbers and impossible dates rather than guessing; two quick edits do not revert each other; tested (UiSheetsEditorLogicTests.swift:13-79). | [PropertiesPanel.swift:514-521](../../Sources/GraphiteUI/PropertiesPanel.swift#L514-L521) |
| Toolbar layout as pure functions | Named thresholds with reasons; tested (WorkspaceFocusModeTests.swift:30-36, PencilToolboxTests.swift:480-504). | [DocumentModeToggle.swift:71-133](../../Sources/GraphiteUI/DocumentModeToggle.swift#L71-L133) |
| Typing does not rebuild the pane | Editor responsiveness is a top priority; the split of autosave out of the view must keep "the pane body never reads the text". | [MarkdownPane.swift:140-145](../../Sources/GraphiteUI/MarkdownPane.swift#L140-L145) |
| Drawing check cancels its file read | Quick cursor moves do not stack disk reads. | [MarkdownPane.swift:733-740](../../Sources/GraphiteUI/MarkdownPane.swift#L733-L740) |
| Theme colors checked per appearance and contrast | A theme can never make note text unreadable or hide the reading highlight. | [NoteThemeStyle.swift:300-315](../../Sources/GraphiteUI/NoteThemeStyle.swift#L300-L315) |
| Numbered equations as pure layouts with fallback | Nothing is cut off at narrow widths; a formula the typesetter cannot draw stays readable. | [NumberedEquationView.swift:21-23](../../Sources/GraphiteUI/NumberedEquationView.swift#L21-L23) |
| Table lines as separate rectangles | Long tables keep their lines (texture size limit), swipes stay with the note. | [MarkdownPreview.swift:2295-2312](../../Sources/GraphiteUI/MarkdownPreview.swift#L2295-L2312) |
| Unique heading scroll targets numbered as the outline numbers them | Outline jumps to the second of two equal headings reach it; tested (UiReadingViewTests.swift:214). | [MarkdownPreview.swift:429-439](../../Sources/GraphiteUI/MarkdownPreview.swift#L429-L439) |
| Narrow capabilities passed as values | These are the shape the pane itself should take (ISP-READING-01). | [PropertiesPanel.swift:8-15](../../Sources/GraphiteUI/PropertiesPanel.swift#L8-L15) |
| Font requests off the main actor | Documents a platform constraint and avoids a crash. | [NoteTypography.swift:57-65](../../Sources/GraphiteUI/NoteTypography.swift#L57-L65) |

### 2.4 MDCORE (18 rows; full evidence in [MDCORE](areas/mdcore.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Table edits as non-overlapping replacements over one UTF-16 layout of the original source | Every edit changes only the characters it must, so padding, outer pipes, indentation, `\r\n` and lone `\r` survive; no reformatting of the user's table. | [MarkdownTable.swift:434-535](../../Sources/GraphiteCore/MarkdownTable.swift#L434-L535) |
| Commands return `MarkdownTextEdit` values | One replacement per command joins the native undo history; rules are tested without UIKit; the same shape serves blocks, folds and colors. | [MarkdownEditing.swift:3-14](../../Sources/GraphiteCore/MarkdownEditing.swift#L3-L14) |
| Exact link ranges with a verified fallback | Renames rewrite only text that provably is the link; a mislocated range degrades to "indexed, not rewritten" instead of corrupting the note. | [MarkdownSemantics.swift:286-548](../../Sources/GraphiteCore/MarkdownSemantics.swift#L286-L548) |
| `SortedRangeSet` | Overlap tests by binary search keep link-dense notes linear; the right primitive to share (CC-MDCORE-02). | [MarkdownSemantics.swift:550-579](../../Sources/GraphiteCore/MarkdownSemantics.swift#L550-L579) |
| Parser and YAML bounds tested on a 512 KB stack | A deeply nested or alias-bomb note still indexes its Wikilinks and tags instead of crashing every launch; the tests reproduce the real stack. | [ParserNestingLimits.swift:9-151](../../Sources/GraphiteCore/ParserNestingLimits.swift#L9-L151) |
| Chunked block-state walk with checkpoints | Styling far down a long note reads only candidate lines through the text-storage proxy; it is the editor's main latency defence. | [MarkdownStyleScanner.swift:213-295](../../Sources/GraphiteCore/MarkdownStyleScanner.swift#L213-L295) |
| Fold keys and region moving | Folds survive edits elsewhere; typing does not rescan the note; the exhaustive equivalence test is the model for every performance mirror. | [NoteFolding.swift:41-46](../../Sources/GraphiteCore/NoteFolding.swift#L41-L46) |
| Hand-written mirror with a parity test | Shows how a fast duplicate can coexist with a single owner. | [NoteFolding.swift:96-135](../../Sources/GraphiteCore/NoteFolding.swift#L96-L135) |
| `DisplayMathLines` pairing in linear time | The right owner for `$$` pairing; the other four rules should call it. | [DisplayMathLines.swift:26-45](../../Sources/GraphiteCore/DisplayMathLines.swift#L26-L45) |
| Data-driven code languages and carried line state | A lexical language is data; the editor restyles only changed lines and stops when stored states agree. | [CodeLanguages.swift:5-162](../../Sources/GraphiteCore/CodeLanguages.swift#L5-L162) |
| Pasted HTML safety and bounds | Malicious or broken pasted HTML cannot inject a script link, bloat the note with base64, or hang the converter. | [HTMLToMarkdown.swift:485-490](../../Sources/GraphiteCore/HTMLToMarkdown.swift#L485-L490) |
| Offsets that survive text rewriting | A tap on a reading-view checkbox changes exactly one character of the note, or nothing. | [NotePreviewDocument.swift:74-87](../../Sources/GraphiteCore/NotePreviewDocument.swift#L74-L87) |
| Line-ending-aware insertion | CRLF notes stay CRLF; a block inserted above `---` does not turn the previous line into a setext heading. | [MarkdownSemantics.swift:1006-1080](../../Sources/GraphiteCore/MarkdownSemantics.swift#L1006-L1080) |
| Defensive numeric parsing | Vault content cannot trap the indexer or make a list marker overflow. | [MarkdownSemantics.swift:181-183](../../Sources/GraphiteCore/MarkdownSemantics.swift#L181-L183) |
| Surrogate-aware word ranges | Bold/italic toggles on words with letters outside the BMP wrap the whole word. | [MarkdownEditing.swift:546-576](../../Sources/GraphiteCore/MarkdownEditing.swift#L546-L576) |
| Color removal semantics and closer rules | The Colors syntax stays ordinary text and removal edits only from the first marker to the last (OBJECTIVE.md:39). | [TextColorMarkup.swift:103-145](../../Sources/GraphiteCore/TextColorMarkup.swift#L103-L145) |
| Plugin code-block location refuses ambiguity | A plugin editing "its" lines can never reach another block. | [LivePreviewBlocks.swift:207-215](../../Sources/GraphiteCore/LivePreviewBlocks.swift#L207-L215) |
| `CodeFence` / `CodeFenceTracker` as the shared fence-length rule | Already the most reused rule (9 consumers); the base the line syntax should grow from (adding the indentation limit). | [MarkdownSemantics.swift:661-679](../../Sources/GraphiteCore/MarkdownSemantics.swift#L661-L679) |

### 2.5 VAULT (24 rows; full evidence in [VAULT](areas/vault.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Revision check inside the coordinated write accessor, by full SHA-256 and size | Same-size external edits and deletions are conflicts; no time window between check and replace inside the coordination. | [AtomicFileWriter.swift:76-91](../../Sources/GraphiteCore/AtomicFileWriter.swift#L76-L91) |
| Staging in the item-replacement folder on the destination volume, `F_BARRIERFSYNC` before the rename, `F_FULLFSYNC` after | A crash never leaves a staged file in a synced vault; power loss leaves the old or the new file. | [AtomicFileWriter.swift:67-127](../../Sources/GraphiteCore/AtomicFileWriter.swift#L67-L127) |
| `VaultPath` as the only path type: NFC, `/`-scalar splitting, `..` refused at the root, symbolic links resolved component by component, re-validated on decode | Closes path escapes and Unicode duplicates for every caller; tested against chained links and combining marks (CoreFilesSettingsFixTests.swift:56-112). | [VaultPath.swift:26-153](../../Sources/GraphiteCore/VaultPath.swift#L26-L153) |
| `move` never replaces, allows a case-only rename, and refuses moving a folder into itself by file identity | Correct on case-insensitive volumes, where a name comparison alone is wrong. | [VaultStore.swift:307-337](../../Sources/GraphiteCore/VaultStore.swift#L307-L337) |
| Free names plus `.absent` writes | The check-then-write race is safe: a name taken in between fails as a conflict instead of overwriting. | [VaultStore.swift:429-455](../../Sources/GraphiteCore/VaultStore.swift#L429-L455) |
| Deletion: coordinated deletion before and outside `trashItem`, fallback to the vault's `.trash` | Presenters let go first; nesting deadlocks on iPadOS; a provider without trash still keeps the file. | [VaultStore.swift:378-415](../../Sources/GraphiteCore/VaultStore.swift#L378-L415) |
| `app.json` written member by member from the settings the change started from | Keys changed in Obsidian meanwhile survive; unknown keys keep exact bytes and position; duplicate keys read as `JSON.parse` reads them. | [ObsidianSettings.swift:224-261](../../Sources/GraphiteCore/ObsidianSettings.swift#L224-L261) |
| Read-modify-write of settings files against the file as it is now, with "unchanged leaves the bytes" | A bookmark added in Obsidian between Graphite's read and write is kept. | [VaultStore.swift:185-202](../../Sources/GraphiteCore/VaultStore.swift#L185-L202) |
| `JSONValue` and `Bookmark.fields` keep every field, whole numbers whole | Unknown bookmark kinds and keys round-trip. | [Bookmarks.swift:5-48](../../Sources/GraphiteCore/Bookmarks.swift#L5-L48) |
| Frontmatter splicing with read-back verification and a fallback | Comments, number spellings and anchors of untouched properties stay byte-exact; a splice that would read differently is refused. | [NoteProperties.swift:72-91](../../Sources/GraphiteCore/NoteProperties.swift#L72-L91) |
| Link rewrites: planned before the move, refused when a link cannot be located, nested replacements merged, BOM kept, each note written only at its planned revision | A real planner/executor split; every failure is reported per note with a reason, never silently. | [VaultFileOperations.swift:88-143](../../Sources/GraphiteIndex/VaultFileOperations.swift#L88-L143) |
| Index scan: prune only after a complete enumeration; per-file failure isolation; refresh during a scan wins over the scan's older reading | A failed listing never deletes rows of files that exist; a save during a scan is never undone. | [VaultIndex.swift:586-638](../../Sources/GraphiteIndex/VaultIndex.swift#L586-L638) |
| One file coordination per batch of note reads, falling back to one per file | The code comment measures it at a tenth of the cost of per-file coordination (:728-730), and one bad file costs only itself. | [VaultIndex.swift:731-747](../../Sources/GraphiteIndex/VaultIndex.swift#L731-L747) |
| Search pages bounded by count and time, continued by sort position, cancellable, regular expressions time-limited | Typing never holds the database; a hostile pattern cannot hang the app. | [VaultSearch.swift:118-206](../../Sources/GraphiteIndex/VaultSearch.swift#L118-L206) |
| `SearchTextTokens` reproduces SQLite's `unicode61` tokenizer | The matcher and FTS5 agree, so exact SQL conditions skip per-note checks; pinned by `CoreSearchQueryUnicode61AgreementTests`. | [SearchQuery.swift:393-553](../../Sources/GraphiteCore/SearchQuery.swift#L393-L553) |
| `SearchSQLCompiler` conditions are supersets unless marked exact | `NOT` of an inexact condition becomes "everything", never a false negative. | [VaultSearch.swift:279-333](../../Sources/GraphiteIndex/VaultSearch.swift#L279-L333) |
| YAML anchor and alias-expansion bounds before and after composing | Stops "billion laughs" and deep alias chains before any walk; iterative, no recursion. | [YAMLAliasExpansionLimits.swift:32-102](../../Sources/GraphiteCore/YAMLAliasExpansionLimits.swift#L32-L102) |
| Conflict versions: discovery never downloads; a kept version is removed only after its separate file is published | Placeholders stay placeholders; no version is lost on a failed copy. | [FileVersionConflicts.swift:51-65](../../Sources/GraphiteApple/FileVersionConflicts.swift#L51-L65) |
| Folder access: bookmark refresh when stale, app-Documents folders remembered by relative path on iOS, scope released on deinit | Survives app updates that move the container and folders moved by the user. | [FolderAccess.swift:8-21](../../Sources/GraphiteApple/FolderAccess.swift#L8-L21) |
| `VaultMonitor`'s one mutable field behind a `Mutex`, serial queue, documented `@unchecked Sendable` | The only unsafe-concurrency escape in the Apple files of this area, with its invariant stated. | [FolderAccess.swift:131-174](../../Sources/GraphiteApple/FolderAccess.swift#L131-L174) |
| File recovery outside the vault, as user content, with sequence suffixes and one shared lock | Same-millisecond and concurrent snapshots are all kept (FileRecoveryTests.swift:83-131). | [FileRecovery.swift:4-72](../../Sources/GraphiteCore/FileRecovery.swift#L4-L72) |
| Pure value types for navigation state: `TabLayout`, `NavigationHistory`, `RecentFiles`, `DocumentPlaceMemory`, `VaultList` | No I/O; invariants enforced in the type; unit-tested without a host. | [TabLayout.swift:44-401](../../Sources/GraphiteCore/TabLayout.swift#L44-L401) |
| `MomentDateFormat.date` accepts a date only if it writes back to the same text | Rejects impossible days (31 April) without a calendar table. | [MomentDateFormat.swift:84-85](../../Sources/GraphiteCore/MomentDateFormat.swift#L84-L85) |
| `Int(clampingWholePartOf:)` for untrusted numbers | Removes the `Int(_:)` trap on `1e300` and `.inf` everywhere it is used. | [WholeNumberConversion.swift:7-15](../../Sources/GraphiteCore/WholeNumberConversion.swift#L7-L15) |

### 2.6 BASES (23 rows; full evidence in [BASES](areas/bases.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Prefilter as a superset with an ASCII escape hatch | Only conjunctions narrow; `or` and `not` add nothing; non-ASCII input skips narrowing and non-ASCII stored text always passes. | [BaseRecordPrefilter.swift:38-40](../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L38-L40) |
| Fail-closed filters | A filter that is not fully read never widens a view; a parse error anywhere blocks the run. | [BaseDefinition.swift:350-354](../../Sources/GraphiteCore/BaseDefinition.swift#L350-L354) |
| YAML-preserving edit with read-back | Unchanged returns the original bytes; splices only changed entries; compares meaning including custom tags; refuses rather than strips. | [BaseDefinitionEditor.swift:60-110](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L60-L110) |
| Supplementary-plane placeholder trick for libyaml | Keeps emoji literal in rewritten lines without `\U` escapes. | [BaseDefinitionEditor.swift:126-146](../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L126-L146) |
| Revision-checked saves, view targets, BOM | Another app's edit is never overwritten; an edit prepared on one view never lands on another; a byte order mark survives. | [BaseDocumentModel.swift:329-347](../../Sources/GraphiteUI/BaseDocumentModel.swift#L329-L347) |
| Checked property rewrite | Compares untouched properties as YAML nodes, refuses nested values, verifies the new value reads back. | [BasePropertyEditing.swift:29-46](../../Sources/GraphiteCore/BasePropertyEditing.swift#L29-L46) |
| Draft-versus-file state in the view editor | A typed `FileChange` instead of booleans; a stale draft cannot be saved over a changed view. | [BaseViewEditorSheet.swift:113-165](../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L113-L165) |
| Stack guards | A hostile `.base` becomes a cell error, not a crash on a 512 KiB thread. | [BaseExpression.swift:281-341](../../Sources/GraphiteCore/BaseExpression.swift#L281-L341) |
| Value equality and hashing | Reflexive with NaN; the exhaustive left-value switch makes a new case a compile error; formula `==` stays separate and documented (BaseValue.swift:336-340). | [BaseValue.swift:78-102](../../Sources/GraphiteCore/BaseValue.swift#L78-L102) |
| Overflow-safe durations | Formula input like `duration("999999999y") * 999999999` never traps. | [BaseValue.swift:42-75](../../Sources/GraphiteCore/BaseValue.swift#L42-L75) |
| JavaScript-compatible text and numbers | Number printing, `toFixed`, `split` and `replace` match Obsidian's JavaScript; UTF-16 `length` and `slice` (BaseEvaluator.swift:327-328, BaseEvaluator.swift:915-919). | [BaseValue.swift:426-470](../../Sources/GraphiteCore/BaseValue.swift#L426-L470) |
| Wall-clock date arithmetic and moment formatting | Daylight-saving and month overflow as JavaScript; English text regardless of device locale; lazily computed fields. | [BaseDateSupport.swift:163-222](../../Sources/GraphiteCore/BaseDateSupport.swift#L163-L222) |
| Regular expression time limit | Catastrophic patterns become a cell error; compiled once per run. | [BaseEvaluator.swift:976-987](../../Sources/GraphiteCore/BaseEvaluator.swift#L976-L987) |
| Folder-keyed link memo | One resolution per folder instead of per row, with the contract stated on the protocol. | [BaseEvaluator.swift:146-165](../../Sources/GraphiteCore/BaseEvaluator.swift#L146-L165) |
| Record reuse by row revision | The invariant is written beside the code; only changed files are re-read. | [BaseRecordReuse.swift:5-17](../../Sources/GraphiteIndex/BaseRecordReuse.swift#L5-L17) |
| Bounded loading | 5,000 records by default, 20,000 maximum, truncation reported (BaseDocumentView.swift:377-380). | [BaseRecordQueries.swift:10-17](../../Sources/GraphiteIndex/BaseRecordQueries.swift#L10-L17) |
| Fast scalar decode with fallback | Handles the common case without `JSONDecoder` and falls back on anything unusual. | [BaseRecordQueries.swift:292-337](../../Sources/GraphiteIndex/BaseRecordQueries.swift#L292-L337) |
| Lookup failure surfaced before publishing | Rows computed from a failed read are never shown (keep the behaviour; move it into the contract per LSP-BASES-02). | [BaseRecordQueries.swift:277-289](../../Sources/GraphiteIndex/BaseRecordQueries.swift#L277-L289) |
| Hardened tile fetching and scheme filtering | No cookies, credentials or disk cache; http(s) only; 4 MB cap; covers never load `file://`. | [BaseTiledMapView.swift:13-65](../../Sources/GraphiteUI/BaseTiledMapView.swift#L13-L65) |
| Inert `html()` | Native text from untrusted markup; nothing runs or loads; bounded size and depth. | [BaseHTMLText.swift:1-58](../../Sources/GraphiteCore/BaseHTMLText.swift#L1-L58) |
| Thumbnail store | Actor-owned budget, one decode per location, file-version invalidation, injectable decoder. | [BaseValueViews.swift:397-526](../../Sources/GraphiteUI/BaseValueViews.swift#L397-L526) |
| Result de-duplication before publishing | An index change after every autosave does not re-lay out every row. | [BaseDocumentModel.swift:228-229](../../Sources/GraphiteUI/BaseDocumentModel.swift#L228-L229) |
| Pure helpers already extracted as statics | Decide-then-do already in place; unit-tested without UI. | [BaseDocumentModel.swift:291-298](../../Sources/GraphiteUI/BaseDocumentModel.swift#L291-L298) |

### 2.7 CANVAS (21 rows; full evidence in [CANVAS](areas/canvas.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| The file's bytes are the document; Graphite's model is a view of them | Unknown keys, types, number spellings and whitespace survive by construction, not by a serializer remembering them. | [CanvasFile.swift:144-175](../../Sources/GraphiteCore/CanvasFile.swift#L144-L175) |
| Position-recording, bounded JSON parser | Byte ranges for every key and value make splicing possible; depth and value-count limits stop hostile files; duplicate keys follow `JSON.parse` (last wins. | [CanvasJSON.swift:93-333](../../Sources/GraphiteCore/CanvasJSON.swift#L93-L333) |
| Edits as splices with inverse patches as undo steps | Undo is exact by construction and stores only changed bytes; a patch for another version is refused, not misapplied (CanvasEditingTests.swift:271-275). | [CanvasFileEditing.swift:56-112](../../Sources/GraphiteCore/CanvasFileEditing.swift#L56-L112) |
| Re-parse after every change before adoption | A splice bug can never reach disk as invalid JSON. | [CanvasFileEditing.swift:101-102](../../Sources/GraphiteCore/CanvasFileEditing.swift#L101-L102) |
| No-op edits write nothing (`setNumber`/`setString` compare values, not bytes) | `10.0`, `-2e1` and `\u0041` stay as written (CanvasEditingTests.swift:23-40). | [CanvasFileEditing.swift:420-437](../../Sources/GraphiteCore/CanvasFileEditing.swift#L420-L437) |
| New entries follow the file's own layout; Obsidian's layout for empty files | Diffs in Git and sync stay one line per change (CanvasEditingTests.swift:92-122). | [CanvasFileEditing.swift:284-345](../../Sources/GraphiteCore/CanvasFileEditing.swift#L284-L345) |
| Removal and reordering keep separators in place | Remaining entries keep their own lines; reorder swaps whole entries. | [CanvasFileEditing.swift:349-400](../../Sources/GraphiteCore/CanvasFileEditing.swift#L349-L400) |
| Unknown card types are shown, preserved, copyable, never synthesised | Plugin card types survive; Graphite never invents fields it does not understand. | [CanvasFile.swift:94-96](../../Sources/GraphiteCore/CanvasFile.swift#L94-L96) |
| Pure Core geometry with tests | Hit testing, snapping, routing and reading order are testable without UI. | [CanvasGeometry.swift:1-399](../../Sources/GraphiteCore/CanvasGeometry.swift#L1-L399) |
| Gestures decided in the session in view coordinates | Finger, Pencil and pointer share one path; `CanvasSessionTests` drives it without a screen. | [CanvasInteraction.swift:18-21](../../Sources/GraphiteUI/CanvasInteraction.swift#L18-L21) |
| Revision-checked saves; looking never writes; conflict → copy or other version | Meets the "never silently overwrite external edits" contract; pinned by CanvasSessionTests.swift:357-389. | [CanvasSession.swift:311-403](../../Sources/GraphiteUI/CanvasSession.swift#L311-L403) |
| A damaged canvas opens nothing and is never rewritten | Unreadable data is left alone. | [CanvasSession.swift:158-164](../../Sources/GraphiteUI/CanvasSession.swift#L158-L164) |
| Level-of-detail layers and board anchoring | A pan changes one transform; float precision stays bounded far from the origin; at most 60 live card views. | [CanvasSession.swift:59-64](../../Sources/GraphiteUI/CanvasSession.swift#L59-L64) |
| Accessibility: reading order, colour names, off-screen elements, zoom-to-element | Colour is never the only cue; every shown card is reachable. | [CanvasGeometry.swift:252-283](../../Sources/GraphiteCore/CanvasGeometry.swift#L252-L283) |
| Link cards accept and open only `http`/`https` | `javascript:`, `file:` and app schemes are refused (CanvasSessionTests.swift:344-353). | [CanvasInteraction.swift:416-431](../../Sources/GraphiteUI/CanvasInteraction.swift#L416-L431) |
| Canvas link targets escape `%` and `#` and start at the vault root | File cards resolve exactly their file, never a same-named note beside the canvas. | [CanvasLinks.swift:89-96](../../Sources/GraphiteCore/CanvasLinks.swift#L89-L96) |
| `GraphLayout` is deterministic d3 with Barnes–Hut and a tested quadtree | Same graph → same layout; the approximation matches the exact force at threshold 0. | [GraphLayout.swift:73-89](../../Sources/GraphiteCore/GraphLayout.swift#L73-L89) |
| Simulation in an actor; drags go through it | Layout work stays off the main thread; pins never race a step. | [GraphCanvas.swift:4-33](../../Sources/GraphiteUI/GraphCanvas.swift#L4-L33) |
| MapKit markers restyled only when highlight or accent changes | Avoids re-clustering thousands of markers on unrelated updates. | [NotesMapView.swift:127-136](../../Sources/GraphiteUI/NotesMapView.swift#L127-L136) |
| Bounded reads of untrusted settings and PDF renders | Settings over 1 MB are ignored; PDF pages are capped at 3,000 px with a 48 MB cache keyed by modification date. | [PlacedNote.swift:19-20](../../Sources/GraphiteCore/PlacedNote.swift#L19-L20) |
| `@unchecked Sendable` with a stated invariant | The only escape in scope names why it is safe (immutable `CGImage`). | [CanvasCardViews.swift:407-408](../../Sources/GraphiteUI/CanvasCardViews.swift#L407-L408) |

### 2.8 INK (21 rows; full evidence in [INK](areas/ink.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| PNG container that never copies and checks every CRC | Ranges index the file directly; a bad CRC on image data is damage, on `grPK` only stale metadata; tests pin slices. | [GraphitePNG.swift:59-94](../../Sources/GraphiteCore/GraphitePNG.swift#L59-L94) |
| Domain-separated visible-content digest plus legacy acceptance | Colour, orientation and animation edits by other apps invalidate the record; older drawings stay editable; a record written now cannot pass the weaker check. | [GraphitePNG.swift:96-131](../../Sources/GraphiteCore/GraphitePNG.swift#L96-L131) |
| Minimal record version computed from content, and a decoder that rejects a record claiming the wrong version | An older build treats newer drawings as plain images instead of re-saving without their pictures; tests cover each version (DrawingGeometryTests.swift:118-283). | [DrawingPayload.swift:248-277](../../Sources/GraphiteCore/DrawingPayload.swift#L248-L277) |
| Binary-plist object count checked before decoding | Prevents stack exhaustion on hostile nested data at launch (CrashLoopRegressionTests.swift:106-115). | [DrawingPayload.swift:356-374](../../Sources/GraphiteCore/DrawingPayload.swift#L356-L374) |
| Read-back verification before a file is returned | Never writes a drawing that an ordinary decoder renders wrongly or that Graphite cannot re-edit. | [DrawingFileService.swift:163-180](../../Sources/GraphiteApple/DrawingFileService.swift#L163-L180) |
| Streaming band encoder with independent decoder check | Peak memory is one band; bands start on whole pixel rows; a black or truncated encode is caught (AppleDrawingFixTests.swift:88-160). | [BandedPNGEncoder.swift:6-119](../../Sources/GraphiteApple/BandedPNGEncoder.swift#L6-L119) |
| SVG reader that accepts only what Graphite writes | Data URIs only (no file or web references), bounded picture bytes, only `rotate(deg cx cy)` about the middle. | [SVGDrawingFile.swift:248-262](../../Sources/GraphiteApple/SVGDrawingFile.swift#L248-L262) |
| Locale-independent, allocation-free number formatting | Clamps instead of trapping; byte output pinned against the previous encoder (AppleDrawingFixTests.swift:701-702). | [SVGDrawingFile.swift:186-216](../../Sources/GraphiteApple/SVGDrawingFile.swift#L186-L216) |
| Eraser-mask-correct vector outlines | Clips the whole outline to the transformed mask instead of `maskedPathRanges`, which misplaces the gaps of moved strokes. | [PencilStrokeSampler.swift:14-61](../../Sources/GraphiteApple/PencilStrokeSampler.swift#L14-L61) |
| Diff-based history steps that refuse foreign drawings and rebuild strokes | History belongs to the document; memory grows with touched strokes; PencilKit's identity cache is defeated. | [PencilDrawingChange.swift:29-125](../../Sources/GraphiteApple/PencilDrawingChange.swift#L29-L125) |
| Pure recognizers and geometry with tests | Thresholds favour leaving strokes alone; iterative RDP cannot exhaust the stack. | [ShapeRecognizer.swift:197-240](../../Sources/GraphiteCore/ShapeRecognizer.swift#L197-L240) |
| Pencil activity as a pure state with explicit times, adapter holding UIKit objects weakly | Lost touch endings cannot freeze scrolling; tested (PalmRejectionTests.swift:94-129). | [PalmRejection.swift:19-92](../../Sources/GraphiteUI/PalmRejection.swift#L19-L92) |
| Palm rejection never delays PencilKit's drawing; observing recognizers never fail | Ink latency is never traded for rejection; a resting hand does not stop hold detection for the next stroke (PencilToolsTests.swift:285-303). | [DrawingEditor.swift:893-909](../../Sources/GraphiteUI/DrawingEditor.swift#L893-L909) |
| Stroke take-back only when every drawing touch is the hand's and no Pencil is down | A Pencil stroke can never be cancelled by it. | [PalmRejection.swift:111-118](../../Sources/GraphiteUI/PalmRejection.swift#L111-L118) |
| Toolbox with intent methods, validation of stored values and injected defaults | Hand-edited or foreign values are clamped; previous-tool memory is one rule; unit tests use a private suite. | [PencilToolbox.swift:128-143](../../Sources/GraphiteUI/PencilToolbox.swift#L128-L143) |
| Laser never saved as the tool in use | Older builds keep reading the toolbox state (PencilToolboxTests.swift:521-536). | [PencilToolbox.swift:265-278](../../Sources/GraphiteUI/PencilToolbox.swift#L265-L278) |
| Draft writes and removals serialized in request order, outside the vault | A removal after closing cannot be overtaken by an earlier write; an earlier draft survives a failed encode. | [DrawingEditorDraftStore.swift:73-138](../../Sources/GraphiteUI/DrawingEditorDraftStore.swift#L73-L138) |
| Selection-frame geometry as static functions | Testable without touches (PicturesAndPaperTests.swift:603-686). | [SelectionFrameView.swift:452-469](../../Sources/GraphiteUI/SelectionFrameView.swift#L452-L469) |
| Lasso move/delete of ink and pictures in one run-loop turn | One undo step for both; pinned by InkSelectionTests.swift:604. | [InkSelection.swift:601-638](../../Sources/GraphiteUI/InkSelection.swift#L601-L638) |
| UI vocabulary for Core enums kept in the UI module | `DrawingPaperPattern` stays free of display text in Core. | [DrawingEditor.swift:58-75](../../Sources/GraphiteUI/DrawingEditor.swift#L58-L75) |
| Light appearance for saved ink | Files look the same in every viewer and appearance. | [PencilStrokeSampler.swift:31-47](../../Sources/GraphiteApple/PencilStrokeSampler.swift#L31-L47) |

### 2.9 LECTURE (33 rows; full evidence in [LECTURE](areas/lecture.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Immutable `PDFEdit` commands applied to the live document and replayed on a baseline snapshot in an actor | A live `PDFDocument` never crosses actors; the file and the open document cannot disagree, and undo is ordinary edits. | [PDFPageManager.swift:21-24](../../Sources/GraphiteApple/PDFPageManager.swift#L21-L24) |
| Revision-checked atomic save with a coordinated read; the written bytes become the baseline only on success | External edits are never overwritten (OBJECTIVE.md), and a failed save keeps every edit. | [PDFPageManager.swift:479-501](../../Sources/GraphiteApple/PDFPageManager.swift#L479-L501) |
| Baseline copies named with the process identifier and cleaned once per launch | iOS skips deinitialisers on termination; textbook-sized copies do not pile up, and a live copy is never removed. | [PDFSession.swift:10-46](../../Sources/GraphiteUI/PDFSession.swift#L10-L46) |
| Conservative compaction: only the single uncompressed cross-reference table; incremental updates, cross-reference streams and encrypted files are refused; the result must open with every page or PDFKit's output is kept | A size optimisation that cannot corrupt a user's PDF. | [PDFObjectCompaction.swift:196-225](../../Sources/GraphiteApple/PDFObjectCompaction.swift#L196-L225) |
| Decide-then-do in compaction: a planner reads, a plan writes into a sink | The same plan writes to memory (export) or to a file (save), and is testable without I/O. | [PDFObjectCompaction.swift:98-174](../../Sources/GraphiteApple/PDFObjectCompaction.swift#L98-L174) |
| Visible ink is standard `/Ink` with `/InkList` centre lines and a filled-outline appearance; the re-editing record sits on exactly one carrier annotation | Every PDF reader shows the ink; Graphite metadata is never needed to render it (OBJECTIVE.md). | [PDFInkAnnotation.swift:35-141](../../Sources/GraphiteApple/PDFInkAnnotation.swift#L35-L141) |
| An ink group is editable only when stroke names match annotations one to one; otherwise it stays read-only and new ink goes into a new group | Another application's edits are never overwritten by stale re-editing data. | [PDFInkAnnotation.swift:260-300](../../Sources/GraphiteApple/PDFInkAnnotation.swift#L260-L300) |
| Incremental ink conversion by stroke fingerprint at PencilKit's stored 32-bit precision | Stroke cost does not grow with the page; undo survives a canvas being rebuilt. | [PDFPencilInk.swift:19-76](../../Sources/GraphiteApple/PDFPencilInk.swift#L19-L76) |
| Ink update merging bounded by the running save | The edit list grows with pages touched, and a save in progress never loses a merged stroke. | [PDFInkAnnotation.swift:222-242](../../Sources/GraphiteApple/PDFInkAnnotation.swift#L222-L242) |
| Kept canvas reused in a new overlay when PDFKit drops the page view | Strokes drawn since the last save survive scrolling. | [GraphitePDFView.swift:1199-1211](../../Sources/GraphiteUI/GraphitePDFView.swift#L1199-L1211) |
| Unrecorded ink is recorded at release, before saves and before rebuilds | No path drops a stroke a canvas shows. | [GraphitePDFView.swift:1332-1338](../../Sources/GraphiteUI/GraphitePDFView.swift#L1332-L1338) |
| Session-owned undo naming pages through `PDFHistoryPage` boxes; steps are ordinary edits | Undo survives view rebuilds and page moves, and two PDFs never share a history. | [PDFEditHistory.swift:19-25](../../Sources/GraphiteUI/PDFEditHistory.swift#L19-L25) |
| Deleting pages first copies them for Undo, and refuses to delete without the copy | Undo can always restore exactly what saving would have written. | [PDFEditHistory.swift:217-252](../../Sources/GraphiteUI/PDFEditHistory.swift#L217-L252) |
| Outline and link destinations are resolved before pages move and restored after | Works around PDFKit's lazy destinations that would point at page 1. | [PDFPageManager.swift:381-464](../../Sources/GraphiteApple/PDFPageManager.swift#L381-L464) |
| Page-tree rewrites re-set Graphite keys and back up `/NM` | Re-editing data and names survive PDFKit's rewrite (keep the behaviour, fix the duplicated key list per OCP-LECTURE-03). | [PDFPageManager.swift:307-328](../../Sources/GraphiteApple/PDFPageManager.swift#L307-L328) |
| Encrypted and permission-restricted PDFs are never written; form widgets are made read-only | PDFKit would drop encryption or typed form values silently. | [PDFSession.swift:346](../../Sources/GraphiteUI/PDFSession.swift#L346) |
| Bounded stream decoding against decompression bombs | A 1 MB embed cannot demand a gigabyte; RULES.md's "bound untrusted metadata". | [PDFDrawingStreamDecoder.swift:26-89](../../Sources/GraphiteApple/PDFDrawingStreamDecoder.swift#L26-L89) |
| Drawing PDF verified by reading the finished file back before returning it | No unreadable drawing is ever saved. | [PDFDrawingFile.swift:31-37](../../Sources/GraphiteApple/PDFDrawingFile.swift#L31-L37) |
| Recording to crash-tolerant media: IMA4 CAF, 1 s MP4 fragments, a new part per interruption, parts joined by passthrough | A lecture survives the app being killed; no re-encoding. | [RecordingController.swift:342-348](../../Sources/GraphiteApple/RecordingController.swift#L342-L348) |
| Publication into the vault is atomic with "expect absent", and the recovery copy is removed only after | Never overwrites a vault file; never loses the only copy. | [RecordingController.swift:9-29](../../Sources/GraphiteApple/RecordingController.swift#L9-L29) |
| A recording that could not be saved blocks new recordings | The only copy of a lecture cannot be replaced by accident. | [RecordingController.swift:86-88](../../Sources/GraphiteApple/RecordingController.swift#L86-L88) |
| Start-attempt token and recorder identity checks on callbacks | Cancelled or overtaken starts leave nothing; a stale recorder cannot finish the current recording. | [RecordingController.swift:109-153](../../Sources/GraphiteApple/RecordingController.swift#L109-L153) |
| `VideoCaptureSource` seam and injectable `RecordingStorage` | A real substitution (camera vs synthetic) exercised by 21 tests through the production writer. | [VideoCapture.swift:81-102](../../Sources/GraphiteApple/VideoCapture.swift#L81-L102) |
| `RecordingState` predicates as the one place transitions are allowed | Views and the controller ask the same questions (`canStart`, `canStop`, `canResume`). | [RecordingState.swift:3-9](../../Sources/GraphiteCore/RecordingState.swift#L3-L9) |
| Watchdog walks the main thread's frames into a preallocated buffer while it is suspended, and is off under a debugger | No allocation while another thread is stopped, so no deadlock. | [MainThreadWatchdog.swift:79-81](../../Sources/GraphiteApple/MainThreadWatchdog.swift#L79-L81) |
| Diagnostics written off the asking thread, outside the vault, bounded to 80 files | Evidence never touches user files and never grows without bound. | [DiagnosticRecords.swift:14-16](../../Sources/GraphiteApple/DiagnosticRecords.swift#L14-L16) |
| Pure, tested decision values: `UnansweredGestureCount`, `PDFResizeZoom`, `RecordingPreviewLayout`, `RecordingControlModel`, `PDFCitation`, `PDFEmbedOptions`, `PageCoordinates` | The shape the rest of the area should take: inputs in, value out. | [PDFPaneHealth.swift:8-77](../../Sources/GraphiteUI/PDFPaneHealth.swift#L8-L77) |
| Thumbnails: page content drawn off the main actor from a mapped copy reopened every 64 pages; byte-bounded shared cache with weak page keys | No whole-textbook rasterising; a released PDF keeps nothing alive. | [PDFThumbnailRenderer.swift:12-34](../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L12-L34) |
| Page identity by object, not index, for selection, rows and drags; drag payload tied to its session | Inserting or moving pages never moves a selection onto other pages. | [PDFPagesSidebar.swift:205-231](../../Sources/GraphiteUI/PDFPagesSidebar.swift#L205-L231) |
| Pictures as standard stamps whose appearance is the picture; bytes under a prefixed key; upright pictures stay under the key older builds read | Every reader shows the picture; older builds keep working on upright ones. | [PDFPicture.swift:7-12](../../Sources/GraphiteApple/PDFPicture.swift#L7-L12) |
| The display-only delegate makes stamps draw smoothly without changing the file; written documents never get it | Display quality without writing anything. | [PDFPicture.swift:278-295](../../Sources/GraphiteApple/PDFPicture.swift#L278-L295) |
| One embed annotates a PDF at a time; other copies are saved first and a stale clean copy is refreshed | Two copies never refuse each other's saves as external changes. | [EmbeddedPDFViewer.swift:644-668](../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L644-L668) |
| Autosave back-off as a pure static function | Slow saves do not rewrite a textbook after every pause; testable with numbers alone. | [PDFSession.swift:479-487](../../Sources/GraphiteUI/PDFSession.swift#L479-L487) |

### 2.10 VOICE (17 rows; full evidence in [VOICE](areas/voice.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Request-identity filtering of speech events | A late callback from a cancelled utterance can never advance or highlight a replacement. | [ReadAloudSpeech.swift:13-21](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L13-L21) |
| Latest-preparation-wins identifiers with revision checks | Stale pages, selections and documents never install themselves. | [ReadAloudController.swift:115](../../Sources/GraphiteUI/ReadAloudController.swift#L115) |
| Refusal instead of guessing in source mapping | A highlight is either exact or absent; repeated words are never relocated by text search. | [ReadAloudDocument.swift:347](../../Sources/GraphiteCore/ReadAloudDocument.swift#L347) |
| Masking that preserves offsets | Every masked character keeps its UTF-16 position and line breaks, so parser ranges map straight back to the note. | [ReadAloudDocument.swift:306-318](../../Sources/GraphiteCore/ReadAloudDocument.swift#L306-L318) |
| PDF highlight validation and ownership | Character counts, composed-character boundaries and the selected text are checked before any highlight. | [PDFReadAloudSource.swift:135-169](../../Sources/GraphiteUI/PDFReadAloudSource.swift#L135-L169) |
| Reveal-once following that yields to touch | It never fights a Pencil stroke or a pinch, and it cannot loop on its own geometry updates. | [PDFReadAloudSource.swift:319-344](../../Sources/GraphiteUI/PDFReadAloudSource.swift#L319-L344) |
| Worker-owned PDFKit objects and a bounded, fall-back-safe extraction | Only immutable values cross actors. | [PDFReadAloudPage.swift:141-180](../../Sources/GraphiteApple/PDFReadAloudPage.swift#L141-L180) |
| The math interpreter is isolated and bounded | An actor owns the JavaScriptCore context. | [ReadAloudMarkdownPreparation.swift:7-22](../../Sources/GraphiteApple/ReadAloudMarkdownPreparation.swift#L7-L22) |
| Pure Core policies with tests | Each is inputs-in, value-out, and has tests (`NeuralReadAloudTests`, `ReadAloudReanchoringTests`, `ReadAloudPlayerAndPenTests`). | [ReadAloudAudioCachePolicy.swift:8-70](../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L8-L70) |
| A cache key that cannot collide and leaves speed out | The NUL separator prevents field-shifting collisions. | [ReadAloudAudioCachePolicy.swift:16-24](../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L16-L24) |
| Manifest and installation safety | Paths cannot escape the voice folder; checksums are well formed. | [NeuralVoiceManifest.swift:155-199](../../Sources/GraphiteCore/NeuralVoiceManifest.swift#L155-L199) |
| Background downloads with resume data and bounded retries | Multi-gigabyte downloads survive suspension and lost connections. | [NeuralVoiceDownloader.swift:40-71](../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L40-L71) |
| Real seams for rendering and alignment | Each protocol exists for a stated reason (no multi-hundred-megabyte model in tests) and has one production implementation. | [ReadAloudPassagePreparation.swift:8-13](../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L8-L13) |
| MLX failure containment | MLX errors become thrown errors before samples are read, so a refused graphics command cannot crash the app. | [NeuralSpeechEngine.swift:44-55](../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L44-L55) |
| The audio session is released only when it is still Read Aloud's | A lecture recording's session is never deactivated by Read Aloud. | [ReadAloudSpeech.swift:296-305](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L296-L305) |
| Personal Voice is asked for only from an explicit tap; robotic voices are never chosen automatically | Respects the permission model and the owner's voice decisions. | [ReadAloudSpeech.swift:65-77](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L65-L77) |
| Rendered audio stays outside the vault | Audio goes to Caches and voices to Application Support, excluded from backup. | [ReadAloudAudioCache.swift:35-38](../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L35-L38) |

### 2.11 PLUGIN (26 rows; full evidence in [PLUGIN](areas/plugin.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Bridge requests are decoded into private `Decodable` structs; failures go back as `{failure: {kind, message}}` answers | A malformed message is `invalidData`, never a crash or a default, and the plugin's promise is rejected with a kind Obsidian's API can map. | [CommunityPluginVaultBridge.swift:34-44](../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L34-L44) |
| Every plugin write is revision-checked (`absent`; `revision`; `replace` reads the current revision); the coordinated write checks again | Plugins never silently overwrite an external edit (OBJECTIVE.md:70). | [CommunityPluginVaultBridge.swift:224-239](../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L224-L239) |
| Plugins' writes go through a second `VaultStore` whose presenter is the runtime's own monitor | Graphite's main presenter sees plugin writes as external changes and updates open notes and the index, while the runtime does not hear its own writes back. | [CommunityPluginHost.swift:358-364](../../Sources/GraphiteUI/CommunityPluginHost.swift#L358-L364) |
| Bridge answers go back to WebKit as JSON text | Note text and vault listings are parsed in WebKit's process, not on the main thread. | [CommunityPluginHost.swift:860-866](../../Sources/GraphiteUI/CommunityPluginHost.swift#L860-L866) |
| Listing runs detached, skips hidden items and symbolic links, caps at 250,000 entries and reports `isTruncated`; background reads skip cloud placeholders | Work stays bounded at 100,000-file scale, and a plugin's metadata scan does not download the whole iCloud vault (OBJECTIVE.md:78). | [CommunityPluginVaultBridge.swift:115-139](../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L115-L139) |
| Text reads drop a leading byte order mark; text writes keep an existing one | Matches `TextDecoder` and preserves the file's encoding bytes (RULES.md:54). | [CommunityPluginVaultBridge.swift:214-217](../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L214-L217) |
| A plugin's edit to the open note becomes one minimal, surrogate-safe edit through the note's session, applied only while the note still has the text the plugin saw | Undo, folds and scroll position survive. | [CommunityPluginEditorChange.swift:12-32](../../Sources/GraphiteCore/CommunityPluginEditorChange.swift#L12-L32) |
| `community-plugins.json` is merged with the file as it is now, written in Obsidian's layout, left untouched when unchanged, created only once a plugin is on, and never overwritten when it is not a list | Obsidian and Graphite share the file without fighting over it. | [CommunityPluginList.swift:18-27](../../Sources/GraphiteCore/CommunityPluginList.swift#L18-L27) |
| `appearance.json` writes only owned keys whose value changed against a baseline, keeping unknown keys' bytes | A key changed in Obsidian in the meantime keeps its value. | [ObsidianAppearance.swift:184-208](../../Sources/GraphiteCore/ObsidianAppearance.swift#L184-L208) |
| The manifest keeps its exact bytes; an identifier is one path component; versions order semantically, pre-releases first | The runtime receives every key the author wrote, and an update never installs a beta over a stable release. | [CommunityPluginManifest.swift:20-54](../../Sources/GraphiteCore/CommunityPluginManifest.swift#L20-L54) |
| The installer checks that the directory's identifier, the current manifest and the release manifest agree; validates the repository and version text; caps every download; never touches `data.json` | A repository cannot install into another plugin's folder, and a plugin's settings survive updates. | [CommunityPluginInstaller.swift:84-128](../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L84-L128) |
| Unreadable plugin folders are listed with their reason rather than dropped | The person sees why a plugin is missing. | [CommunityPluginInventory.swift:134-146](../../Sources/GraphiteCore/CommunityPluginInventory.swift#L134-L146) |
| Consent is per vault and per device, and only enabled plugins run; forgetting a vault removes its consent, secrets and web storage | Matches Obsidian's restricted mode, and nothing is left behind for a forgotten vault. | [CommunityPluginHost.swift:287-310](../../Sources/GraphiteUI/CommunityPluginHost.swift#L287-L310) |
| The scheme handler serves only the bundled runtime folder and vault files resolved through `VaultPath`: read-only, size-capped, and never answering a stopped task | `getResourcePath` works without opening the file system to the page. | [CommunityPluginWebContent.swift:36-106](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L36-L106) |
| The navigation policy refuses anything that would replace the runtime page; only http, https and mailto links leave the app | One stray link cannot end every plugin. | [CommunityPluginWebContent.swift:138-152](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L138-L152) |
| The message receiver is a separate object that holds the host weakly | WebKit retains its message handlers strongly, yet the host can still go away with its vault. | [CommunityPluginWebContent.swift:109-119](../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L109-L119) |
| Copies of plugin output run no page script (`allowsContentJavaScript = false`) and use a non-persistent store; Graphite's script runs in its own content world; the morph keeps a field that is being typed in | Plugin HTML shown in notes cannot run code, and typing in a copy loses no keys. | [CommunityPluginReadingBlocks.swift:755-768](../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L755-L768) |
| The hidden web view is parked inside the window | Plugins' timers keep their full rate without a visible panel. | [CommunityPluginPresentation.swift:29-42](../../Sources/GraphiteUI/CommunityPluginPresentation.swift#L29-L42) |
| Typing events are ordered (each waits for the previous answer) and capped at 512 Ki UTF-16 units; only the latest revision's suggestions are shown | Plugins that track the cursor see changes in order, and stale suggestions never appear. | [CommunityPluginTyping.swift:31-70](../../Sources/GraphiteUI/CommunityPluginTyping.swift#L31-L70) |
| Theme measurement: WebKit measures the theme against Graphite's default layer and only differing values become tokens; results are cached by a SHA-256 of all inputs plus the layer version; one measurement runs at a time and identical requests share it; a 15 s deadline cancels the loser; a generation counter stops a late measurement from releasing the next one's web view | Exact CSS semantics without a CSS engine of Graphite's own, at a bounded cost per change. | [ThemeTokenResolver.swift:20-27](../../Sources/GraphiteUI/ThemeTokenResolver.swift#L20-L27) |
| `AccentLegibility` and `ThemeContrastGuard` are pure functions with WCAG constants and tests | A theme can never make note text unreadable. | [AccentLegibility.swift:7-86](../../Sources/GraphiteCore/AccentLegibility.swift#L7-L86) |
| Secrets stay out of the vault, one item per vault, capped at 1 MB, in the data protection keychain when the process may use it | API keys never sync through the vault, as in Obsidian. | [CommunityPluginSecretStore.swift:7-63](../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L7-L63) |
| Plugin network requests run natively, only for http and https, bounded to 64 MB and 60 s | Obsidian-mobile parity without CORS limits, with bounds. | [CommunityPluginNetworkRequest.swift:13-54](../../Sources/GraphiteCore/CommunityPluginNetworkRequest.swift#L13-L54) |
| Plugin writes to `appearance.json` go through a whitelist of seven keys with validated values | A plugin can write neither arbitrary keys nor a theme name that is a path. | [CommunityPluginThemes.swift:65-87](../../Sources/GraphiteUI/CommunityPluginThemes.swift#L65-L87) |
| Logging marks plugin details private in release builds | Plugin messages can name notes. | [CommunityPluginHost.swift:154-160](../../Sources/GraphiteUI/CommunityPluginHost.swift#L154-L160) |
| A terminated content process restarts the runtime | Memory pressure on iPad does not leave plugins dead. | [CommunityPluginHost.swift:442-450](../../Sources/GraphiteUI/CommunityPluginHost.swift#L442-L450) |

### 2.12 RUNTIME (25 rows; full evidence in [RUNTIME](areas/runtime.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Writes state their expectation: `revision` after a read or write, `replace` otherwise, `absent` for `create`. A conflict is refused, reported as `plugin.writeConflict` and thrown, never overwritten. | This is OBJECTIVE.md's "never silently overwrite another application's changes", applied to plugins. | [vault.js:172-196](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L172-L196) |
| Same-path writes run in turn, each expecting the revision the previous one left; the expectation is read when the turn comes. | Matches Obsidian's last-write-wins for one plugin's quick saves without weakening the conflict check against others. | [vault.js:197-216](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L197-L216) |
| `process` re-reads and re-applies on conflict, and skips the write when the text is unchanged. | The transform always applies to the current file, and an unchanged note is never rewritten (RULES.md: indexing and preview must not rewrite files). | [vault.js:248-283](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L248-L283) |
| An unreadable `types.json` is not overwritten: a failed `process` writes only when the file does not exist. | Unreadable data is left alone, the rule the synthesis states. | [plugins.js:776-781](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L776-L781) |
| Missing Obsidian settings files read as `{}` and nothing is written until a plugin writes. | Opening a vault with plugins creates no files the person did not ask for. | [vault.js:154-165](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L154-L165) |
| The host transport is the one injected seam, with a Node harness that loads the real page in `index.html` order against a temporary folder. | Tests exercise production scripts, not copies. | [foundation.js:30-49](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L30-L49) |
| Vault reads and listings are answered as JSON text parsed in WebKit, not on the app's main thread. | Keeps large notes and listings off the main thread (RULES.md concurrency). | [host-connection.js:11-13](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-host-connection.js#L11-L13) |
| Unsupported APIs throw a named error and are reported once per plugin and feature. | No fake success: RULES.md's "accurately communicate why it is unavailable". | [foundation.js:51-110](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L51-L110) |
| Desktop modules are stand-ins that fail only when used, saying which member was reached. | Cross-platform plugins load on mobile as in Obsidian mobile, and failures stay visible. | [plugins.js:145-184](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L145-L184) |
| ES5-compiled plugins can extend ES2015 classes through `callableClass`, with the class's own prototype, so `instanceof` is exact. | Execution compatibility without patching plugin code (OBJECTIVE.md's plugin goal). | [plugins.js:47-85](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L47-L85) |
| Plugin attribution through `sourceURL` where stacks show it and blob addresses where they do not, decided by a probe. | Failures and unsupported features name the right plugin in WebKit and in V8 alike. | [plugins.js:93-143](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L93-L143) |
| Metadata reads are bounded: 4 MiB per note, 4 at once, cloud-only notes skipped, only metadata kept. | OBJECTIVE.md: no uncontrolled cloud downloads, no whole vault in memory. | [metadata.js:14-18](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L14-L18) |
| Positions are in UTF-16 code units, as CodeMirror and `NSString` count. | Edits computed in the runtime land at the same place in Graphite's editor. | [metadata.js:37-45](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L37-L45) |
| Editor changes made in one synchronous turn reach the host as one change. A refused change brings the current note back, and a newer local change is not overwritten by an older answer. | One undoable edit per command, and no edit applies to text the plugin did not see. | [workspace.js:365-396](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L365-L396) |
| `dom-extensions.js` never replaces an existing member. | WebKit's own `Array.prototype.findLast`-style members win; the runtime adds only what is missing. | [dom-extensions.js:7-15](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-dom-extensions.js#L7-L15) |
| `runtime.receive` never throws: unknown operations and handler failures become `{ failure: { kind, message } }`. | The host always gets an answer it can read. | [plugins.js:1541-1550](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1541-L1550) |
| Copies are bounded and deduplicated: 4 MiB per copy, 60 ms gathering, a signature check before sending, a theme dropped from copies before the 3 MiB style budget is exceeded. | A runaway plugin cannot build an unbounded message to the app. | [reading.js:17-25](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L17-L25) |
| A section is kept as the plugin's only when the plugin changed what it shows; otherwise Graphite keeps its native rendering. | Native rendering and responsiveness stay the default. | [reading.js:493-513](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L493-L513) |
| Task checkboxes in sections are mapped to their note lines, so the host ticks the task in the note. | The edit goes through Graphite's editor, not a plugin write. | [reading.js:468-481](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L468-L481) |
| Links in plugin content go through the host; `window.open` accepts only `http`, `https` and `mailto`. | The page is never replaced by an anchor link, and other schemes are refused. | [reading.js:744-765](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-reading.js#L744-L765) |
| Listener-gated host work: the host sends typing, menus and paste only while some plugin listens. | Protects editor responsiveness when no plugin cares (OBJECTIVE.md priority). | [workspace.js:728-745](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L728-L745) |
| A new page per vault start: every module-level registry lives exactly as long as one vault's session. | Vault-switch cleanup needs no per-feature code in the runtime. | [CommunityPluginHost.swift:371-401](../../Sources/GraphiteUI/CommunityPluginHost.swift#L371-L401) |
| The shared variable layer is all zero-specificity `:where` rules. | A theme overrides every default, as in Obsidian. | [graphite-default-variables.css:8-9](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L8-L9) |
| Named limits with units: `maximumIndexedNoteBytes`, `concurrentNoteReads`, `pluginScriptLoadMilliseconds`, `suggestionWaitMilliseconds`, `maximumSnapshotCharacters`, `snapshotDelayMilliseconds`, `processorWaitMilliseconds`, `maximumCopyStyleCharacters`. | The model for CC-RUNTIME-04's fix. | [metadata.js:16-18](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L16-L18) |
| Naming follows RULES.md: `pluginIdentifier`, `normalizedPath`, `eventReference`, `isReloadNeeded`; abbreviations appear only where Obsidian's API names them (`cls`, `attr`, `ctime`, `docId`). Comments mostly state the current rule with the plugin that needs it. | Each compatibility shim says which plugin it exists for, which keeps cleanup from deleting it. | [vault.js:197-200](../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L197-L200) |

### 2.13 ARCH (20 rows; full evidence in [ARCH](cross-cutting/architecture.md), section 6)

| Keep | Why | Evidence |
| --- | --- | --- |
| Module direction: Core ← Index, Apple ← Voices ← UI; Core free of UI and platform frameworks | Every Obsidian-format rule can be tested on macOS without UIKit; the split proposed in part 7 extends this instead of replacing it. | [Package.swift:24-38](../../Package.swift#L24-L38) |
| Thin app target | The app target is the natural composition root; only construction needs to move there. | [project.pbxproj:305-312](../../Graphite.xcodeproj/project.pbxproj#L305-L312) |
| Pinned, recorded dependencies | Reproducible builds; vendored patches are listed (RULES.md). | [Package.swift:14-21](../../Package.swift#L14-L21) |
| Swift 6 language mode on package and app | The compiler forces every mutable static onto a global actor or into an explicit `nonisolated(unsafe)`; there are only 4 of the latter (part 8). | [Package.swift:1](../../Package.swift#L1) |
| Every `@unchecked Sendable` states its invariant | 20 of 20 carry a reason (part 8); this is the template for the `assumeIsolated` uses. | [FolderAccess.swift:131-135](../../Sources/GraphiteApple/FolderAccess.swift#L131-L135) |
| Graphite's own writes coordinate with the vault's presenter | External-change detection stays exact without suppress-lists. | [WorkspaceModel.swift:278-279](../../Sources/GraphiteUI/WorkspaceModel.swift#L278-L279) |
| External-change debounce with a cap and a whole-vault threshold, classified off the main thread | `externalRefreshDeadline` is a pure function and `ExternalChangeRefresh` a value type: both already follow "decide, then do". | [WorkspaceModel.swift:1226-1283](../../Sources/GraphiteUI/WorkspaceModel.swift#L1226-L1283) |
| Run identifiers so late results of an old vault are dropped | Correct "latest wins" semantics; the shared primitive (CC-ARCH-04) should keep exactly this behaviour. | [WorkspaceModel.swift:523-541](../../Sources/GraphiteUI/WorkspaceModel.swift#L523-L541) |
| Vault identifier fixed before anything is recorded; index named by it | Survives container moves on iOS updates; legacy index migrated once. | [WorkspaceModel.swift:271-272](../../Sources/GraphiteUI/WorkspaceModel.swift#L271-L272) |
| Unknown stored entries preserved | Matches "unreadable data is moved aside, never overwritten"; extend to tab layouts and places. | [VaultLibrary.swift:69-109](../../Sources/GraphiteUI/VaultLibrary.swift#L69-L109) |
| Disposable, migrated index with named migrations | Order-stable schema evolution; a migration that empties tables relies on the cache being rebuildable. | [VaultIndex.swift:80-187](../../Sources/GraphiteIndex/VaultIndex.swift#L80-L187) |
| Device-only secrets in the keychain, one item per vault | Secrets never enter the vault; the Mac fallback is detected, not assumed. | [CommunityPluginSecretStore.swift:7-68](../../Sources/GraphiteApple/CommunityPluginSecretStore.swift#L7-L68) |
| Serialized draft store | Unsaved strokes are user content kept outside the vault, written in request order. | [DrawingEditorDraftStore.swift:73-138](../../Sources/GraphiteUI/DrawingEditorDraftStore.swift#L73-L138) |
| Places recorded synchronously before the save task | A measured ordering rule (window resize for snapshots); keep it as an invariant (ARCH-INV-14). | [GraphiteRootView.swift:227-237](../../Sources/GraphiteUI/GraphiteRootView.swift#L227-L237) |
| Save serialization in `MarkdownSession.save()` | Autosave, navigation and ⌘S never race; callers only need to stop swallowing its error. | [MarkdownSession.swift:142-175](../../Sources/GraphiteUI/MarkdownSession.swift#L142-L175) |
| Background save assertion on leaving the screen | Gives coordinated writes to iCloud time to finish. | [GraphiteRootView.swift:486-504](../../Sources/GraphiteUI/GraphiteRootView.swift#L486-L504) |
| Deep links queued until the last vault is restored | A link that launches the app acts on the right vault. | [GraphiteRootView.swift:203-211](../../Sources/GraphiteUI/GraphiteRootView.swift#L203-L211) |
| One owner for frontmatter location in Swift | The example to follow for links and media classification. | [MarkdownSession.swift:355](../../Sources/GraphiteUI/MarkdownSession.swift#L355) |
| Error alert titled by its first sentence | Follows Apple's guidance; the one presenter (CC-ARCH-01) should adopt its rule. | [MessageAlert.swift:6-34](../../Sources/GraphiteUI/MessageAlert.swift#L6-L34) |
| Diagnostics outside the vault, bounded | 80-file cap, ordered writes on one queue, nothing synced. | [DiagnosticRecords.swift:4-57](../../Sources/GraphiteApple/DiagnosticRecords.swift#L4-L57) |

## 3. Target module layout and import rules

### 3.1 The layout today

[Package.swift](../../Package.swift) declares five library targets and one executable: `GraphiteCore` (101 files; imports swift-markdown and Yams), `GraphiteIndex` (7; Core and GRDB), `GraphiteApple` (36; Core), `GraphiteVoices` (12; Core, Apple, MLX), `GraphiteUI` (153; everything, plus Textual) and `GraphiteBenchmarks`. The platform floors are iOS 18 and macOS 27.0 ([Package.swift:6](../../Package.swift#L6)). The app target imports `GraphiteUI` only ([GraphiteApp.swift:2](../../App/GraphiteApp.swift#L2)). Direction is enforced for the first four layers and not at all inside `GraphiteUI` (`SRP-ARCH-02`). `GraphiteCore` is not platform-free in the way its import list suggests: nine files call `FileManager`, `URLSession` or the file coordinator (`AtomicFileWriter`, `VaultStore`, `FileRecovery`, `RecordingRecovery`, `CommunityPluginVaultBridge`, `CommunityPluginInstaller`, `CommunityPluginNetworkRequest`, `ObsidianThemes`, and the symbolic-link check in `VaultPath`; `SRP-ARCH-03`, `DIP-ARCH-05`). The import lists of Core are otherwise Foundation, CoreGraphics, Markdown, Yams, CryptoKit, zlib and Synchronization, which stay its only allowed imports.

### 3.2 The target layout

Direction runs one way: a module imports only modules listed in its row. Every row is a SwiftPM target (owner question 1 decides whether the feature rows are targets or folders; the rules do not change).

| Module | Single responsibility | Imports (and only these) | Third-party and platform frameworks it may import |
| --- | --- | --- | --- |
| `GraphiteCore` | Values, parsers, policies, planners, and the ports that several layers consume (`DocumentFileAccess`, `ApplicationClock`, `HTTPDownloading`, the lifecycle observer protocols). No I/O. | none | Foundation, CoreGraphics, CryptoKit, zlib, Synchronization, swift-markdown, Yams |
| `GraphiteStorage` | Vault file I/O and app-private files: `VaultFiles`, `VaultFileManagement`, `AtomicFileWriter`, `VaultBoundary` (symbolic-link and path validation), Obsidian configuration files, `FileRecoveryStore`, `RecordingRecoveryStore`, `DeviceStateStore` | Core | Foundation |
| `GraphiteIndex` | The disposable SQLite cache and its query families | Core, Storage | GRDB |
| `GraphiteApple` | Platform adapters: folder access and bookmarks, PDFKit and PencilKit file writers, AVFoundation recording, Vision, keychain, `NSFileVersion`, speech, diagnostics, `URLSessionHTTPDownloader`, the scanned PDF's text layer, the system's folder icons and Finder's folder looks | Core, Storage | UIKit, AppKit, PDFKit, PencilKit, AVFoundation, Vision, Security, MetricKit, ImageIO, CoreText, CoreImage, QuickLookThumbnailing, UniformTypeIdentifiers |
| `GraphiteVoices` | On-device neural voices: model loading, rendering, cache, downloader | Core, Apple | MLXAudioTTS |
| `GraphiteDesign` | Shared SwiftUI vocabulary: design tokens, chrome, `MessageAlert`, icons derived from descriptors, shared words of the string catalogue | Core | SwiftUI |
| `GraphiteMarkdownRendering` | Drawing primitives that the editor and the reading view both draw with: `ObsidianMarkdownText`, `CalloutView`, `ReadingImageCache`, `EmbeddedMediaPlayers`, reading text styles, `NoteTypography`, `NoteThemeStyle` | Core, Design | SwiftUI, Textual |
| `GraphiteMarkdownEditing` | The note editor: `NativeMarkdownEditor`, `MarkdownDocument`, Live Preview, styling, completion, paste and drop | Core, Apple, Design, MarkdownRendering | UIKit, AppKit, Textual |
| `GraphiteReading` | Reading view, note inspector (outline, links, tags, footnotes, mentions), properties panel | Core, Design, MarkdownRendering | SwiftUI |
| `GraphitePDF` | PDF notebooks: session parts, annotation coordinator parts, pages sidebar, embedded viewer | Core, Apple, Design, MarkdownRendering | PDFKit, PencilKit |
| `GraphiteRecording` | Recording flow, controls and recovery presentation | Core, Apple, Design | AVFoundation |
| `GraphiteInk` | Pencil toolbox and preferences, history canvas, drawing editor, ink selection, lasso | Core, Apple, Design | PencilKit, UIKit |
| `GraphiteCanvas` | JSON Canvas session, board, cards | Core, Design, MarkdownRendering | SwiftUI, UIKit, AppKit |
| `GraphiteGraphAndMap` | Link graph and notes map presentations | Core, Design | SwiftUI, MapKit |
| `GraphiteBases` | Bases document model, views, embedding | Core, Design, MarkdownRendering | SwiftUI, MapKit |
| `GraphiteReadAloud` | Read Aloud controller parts, navigator, player, settings, pronunciation editor | Core, Apple, Voices, Design | AVFoundation, MediaPlayer, PencilKit, PDFKit |
| `GraphitePlugins` | Plugin session, runtime channel, resource scripts, theme resolver, plugin settings and install flows | Core, Apple, Design | WebKit |
| `GraphiteShell` | `WorkspaceModel` as router, `OpenVault`, `TabWorkspace`, sidebar, command catalogue, `PresentationRouter`, root view, document-kind composition | every module above | SwiftUI |
| App target | Composition root: `LaunchMode`, the live, hosted-test and voice-benchmark compositions, the feature registration list, scenes | every module above | SwiftUI |
| `GraphiteBenchmarks` (executable) | Index and voice measuring tools; no code from the app imports it | Core, Index, Voices | none |
| `GraphiteFixtures` (test-only) | In-memory and failing fakes, builders, `ManualClock`, value fixtures; no XCTest, so previews may import it under `#if DEBUG` | Core, Storage, Index, Apple | Foundation |
| `GraphiteTestSupport` (test-only) | `TemporaryVault`, `IsolatedDeviceState`, `awaitCondition`, hosted windows and touch synthesis, contract suites | Fixtures, every module under test | XCTest |

Added 2026-10-21, for the notebook import: every module may import a standalone package of section 3.5, which imports no Graphite module; today that is `NotebookImport`, which `GraphiteApple` (the import's PDF and recording writers) imports. `scripts/check-imports.py` lists the packages (`STANDALONE_PACKAGES`) and refuses a Graphite import under `Packages/`.

Added 2026-10-21, for document scanning and folder looks: `GraphiteApple` may import CoreText (the invisible text of a scanned PDF), CoreImage (the mask that removes a picture's background), QuickLookThumbnailing (the system's own icon of a folder on iOS) and UniformTypeIdentifiers (the type of an image it encodes). Today's `GraphiteUI`, until it is cut into the feature modules above, may import VisionKit (the system's document scanner), PhotosUI (the photo picker) and UniformTypeIdentifiers (file types of pickers, drops and exports); `scripts/check-imports.py` lists them in its rows.

```
App target ── LaunchMode, live / hosted-test / voice-benchmark compositions, feature registration list
   │
GraphiteShell ── WorkspaceModel (router), OpenVault, TabWorkspace, commands, PresentationRouter, document-kind composition
   │
   ├─ feature modules, none imports another:
   │    MarkdownEditing  Reading  PDF  Recording  Ink  Canvas  GraphAndMap  Bases  ReadAloud  Plugins
   │      each imports only ↓ (Apple / Voices where its row says so)
   │
GraphiteMarkdownRendering ─┐
GraphiteDesign ────────────┤
GraphiteVoices ── Apple    │            GraphiteIndex ── Storage
GraphiteApple ── Storage ──┴───────────────────────┐          │
GraphiteStorage ───────────────────────────────────┴── GraphiteCore (no I/O, no frameworks beyond Foundation)
```

### 3.3 Import rules

1. **Direction is enforced by `Package.swift`.** A target lists exactly the dependencies of its row; a cycle or an upward import is a build error. Until the feature rows are targets, `scripts/check-imports.py` enforces the same table over folders (`FR-54`).
2. **Features never import features.** A feature talks to another through a port declared in Core or in its own module and supplied by `GraphiteShell` or the app target. The only code that names two features is the document-kind composition in `GraphiteShell` (a note pane needs the editor, the reading view and the inspector) and the registration list in the app target. Embedding (a PDF, a base or a note inside a note or a canvas card) goes through `EmbeddedContentRenderers`, a value the shell puts into the SwiftUI environment, keyed by `DocumentKind` (`DIP-EDITOR-02`, `OCP-ARCH-01`).
3. **Features import neither `GraphiteStorage` nor `GraphiteIndex`.** A feature receives `DocumentFileAccess`, `VaultFileManagement` or its own read port (`BaseRecordSource`, `ReadingFileLookup`), never `VaultStore` or `VaultIndex` (`ISP-VAULT-01`, `ISP-BASES-01`, `ISP-CANVAS-04`, `FR-39`). This is stricter than the architecture audit's table, which lets features read the index.
4. **Ports belong to the consuming layer.** A port consumed by two or more modules is declared in Core; a port with one consumer is declared in that module. Adapters implement ports and never declare vocabulary the preferences or features use (`DIP-ARCH-05`, `FR-54`).
5. **Third-party and platform frameworks are confined.** MLX only in `GraphiteVoices`, GRDB only in `GraphiteIndex`, swift-markdown and Yams only in Core, WebKit only in `GraphitePlugins`, MapKit only in `GraphiteBases` and `GraphiteGraphAndMap`, Textual only in `GraphiteMarkdownRendering` and `GraphiteMarkdownEditing` (nine `GraphiteUI` files import it today: the editor's styler, concealed-replacement layout fragment, Live Preview widgets and table editing, the code colours, and the reading view's preview, equations, source alignment and task checkbox).
6. **Platform conditionals hold platform calls only.** A `#if os` block contains calls into UIKit or AppKit and nothing that decides (`FR-06`, `FR-26`).
7. **Cross-module visibility uses `package`, not `public`,** when the feature modules are targets, so a type shared by the shell and a feature is not part of a public API (owner question 1).
8. **Test targets follow the module of the type under test** ([testing.md](testing.md) 4.1, `FR-84`); `GraphiteTestSupport` and `GraphiteFixtures` are linked into test targets only, never into the app.

### 3.4 Where each current file group goes

| Area | Current files | Target |
| --- | --- | --- |
| [SHELL](areas/shell.md) | `GraphiteRootView`, `GraphiteMacScenes`, `WorkspaceModel` and its 23 extension files, `GraphiteCommands`, `WorkspaceCommands`, `QuickPalette`, `VaultSidebar*`, `VaultSwitcher`, `VaultLibrary`, `TabSwitcher`, `SettingsView`, `WorkspaceFocusMode`, `WorkspacePanes`, `PresentedScreenObserver` | `GraphiteShell`, split by section 6; `GraphitePreferences` splits per feature area (`SRP-SHELL-06`); `MessageAlert` to `GraphiteDesign`; `GraphiteApp.swift` stays in the app target |
| [VAULT](areas/vault.md) | Core: `VaultPath`, `Bookmarks`, `SearchQuery`, `LinkRewriter`, `LinkCompletion`, `LinkGraph`, `GraphLayout`, `NoteProperties`, `TagsAndProperties`, `Templates`, `ObsidianSettings`, `ConflictVersions`, `VaultList`, `VaultURI`, `DocumentPlaces`, `TabLayout`, `Navigation`, `PlacedNote`; I/O: `VaultStore`, `AtomicFileWriter`, `FileRecovery`; Index: all 7; Apple: `FolderAccess`, `FileVersionConflicts` | Pure values stay in Core; `VaultStore`, `AtomicFileWriter`, `FileRecovery` and the symbolic-link check of `VaultPath` move to `GraphiteStorage`; `VaultIndex` splits into families inside `GraphiteIndex`; Apple files stay |
| [MDCORE](areas/mdcore.md) | `MarkdownEditing`, `MarkdownSemantics`, `MarkdownStyleScanner`, `NoteBlocks`, `NoteFolding`, `NotePreviewDocument`, `TextColorMarkup`, `Footnotes`, `LivePreviewBlocks`, `HTMLToMarkdown`, `MarkdownTable`, `DisplayMathLines`, `LaTeXCompatibility`, `Mentions`, `ObsidianPreviewText`, `CodeFormatting`, `CodeLanguages`, `CodeSyntaxHighlighting`, `ParserNestingLimits`, `YAMLAliasExpansionLimits`, `TimeLimitedRegularExpression`, `MathSpeech` | Stay in `GraphiteCore`, one file per concept (Phase 3); the `Mutex` token cache becomes an instance owned by the reading renderer |
| [EDITOR](areas/editor.md) | `NativeMarkdownEditor`, `MarkdownSession`, `MarkdownEditorStyling`, `MarkdownTextStyler`, `MarkdownEditorRetention`, `MarkdownBlockContextCheckpoints`, `LivePreview*`, `ConcealedReplacementLayoutFragment`, `EditorCompletion`, `EditorContextMenu`, `EditorKeyboardToolbar`, `TableCellTextField` | `GraphiteMarkdownEditing`; `NoteTypography` and `NoteThemeStyle` to `GraphiteMarkdownRendering` |
| [READING](areas/reading.md) | `MarkdownPreview` (64 types), `MarkdownPane`, `FilePreviewPane`, `PropertiesPanel`, `DocumentModeToggle`, `ReadingSourceAlignment`, `ReadingTaskCheckbox`, `CalloutFoldStore`, `NumberedEquationView` | Drawing primitives to `GraphiteMarkdownRendering`; builder, scroll restoration, inspector model, properties panel to `GraphiteReading`; `MarkdownPane` becomes the markdown document-kind composition in `GraphiteShell` |
| [BASES](areas/bases.md) | Core: all `Base*` files; Index: `BaseRecordQueries`, `BaseRecordReuse`; UI: `Base*View`, `BaseDocumentModel`, `BaseEmbedding`, `BaseValueViews`, `BaseTiledMapView`, `BaseMapView` | Core and Index files stay (the evaluator is pure and the plugin bridge reads Bases results); UI files to `GraphiteBases` |
| [CANVAS](areas/canvas.md) | Core: `Canvas*`; UI: `CanvasSession`, `CanvasBoard*`, `CanvasCardViews`, `CanvasInteraction`, `CanvasPane`, `GraphCanvas`, `GraphViews`, `MapViews`, `NotesMapView` | Core stays; canvas UI to `GraphiteCanvas`; graph and map views to `GraphiteGraphAndMap` |
| [INK](areas/ink.md) | Core: `DrawingPayload`, `GraphitePNG`, `ShapeRecognizer`, `HandwritingTidying`, `PictureRotation`, `PageCoordinates`; Apple: `DrawingFileService`, `DrawingPictures`, `BandedPNGEncoder`, `SVGDrawingFile`, `VectorDrawing`, `PencilShapes`, `EvenHighlighter`, `PencilStrokeSampler`, `PictureEditing`; UI: `HistoryCanvasView`, `InkSelection`, `LassoTools`, `Pencil*`, `PalmRejection`, `StrokeHold`, `DrawingEditor`, `DrawingEditorDraftStore`, `SelectionFrameView`, `LaserPointer*` | Core and Apple files stay; UI files to `GraphiteInk` |
| [LECTURE](areas/lecture.md) | Core: `RecordingState`, `RecordingRecovery`, `PDFCitation`; Apple: `PDFPageManager`, `PDFDrawingFile`, `PDFInkAnnotation`, `PDFPicture`, `PDFMarkup`, `PDFStructureInspection`, `PDFTemplateGenerator`, `RecordingController`, `VideoRecording`, `VideoCapture`, `MoviePartWriter`, `CameraCaptureSource`; UI: `PDFSession`, `PDFEditHistory`, `GraphitePDFView`, `PDFPane`, `PDFPagesSidebar`, `PDFPaneHealth`, `PDFPageLasso`, `EmbeddedPDFViewer`, `RecordingControls` | Pure values stay in Core, the recovery store to `GraphiteStorage`; Apple adapters stay; PDF UI to `GraphitePDF`; recording UI and `RecordingFlow` to `GraphiteRecording` |
| [VOICE](areas/voice.md) | Core: `ReadAloud*`, `NeuralVoiceManifest`, `PCMWaveFile`; Apple: `ReadAloudSpeech`, `ReadAloudLanguage`, `ReadAloudMarkdownPreparation`, `PDFReadAloudPage`; Voices: all 12; UI: `ReadAloudController`, `ReadAloudNavigator`, `ReadAloudControls`, `ReadAloudFloatingPlayer`, `ReadAloudNowPlaying`, `ReadAloudPen`, `ReadAloudReader`, `ReadAloudVoices`, `ReadAloudVoiceSettings`, `ReadAloudPronunciationEditor`, `NeuralVoiceSettings`, `NeuralVoiceBenchmarkScreen` | Core, Apple, Voices files stay; UI to `GraphiteReadAloud`; `ReadAloudVoices` statics are deleted; `NeuralVoiceBenchmark` and `NeuralVoiceBenchmarkScreen` move to the benchmark target (`DIP-VOICE-05`) |
| [PLUGIN](areas/plugin.md) | Core: `CommunityPluginManifest`, `CommunityPluginList`, `CommunityPluginInventory`, `CommunityPluginEditorChange`, `CommunityPluginInstaller`, `CommunityPluginNetworkRequest`, `CommunityPluginVaultBridge`, `ObsidianThemes`, `ObsidianAppearance`, `VaultThemeTokens`, `AccentLegibility`; Apple: `CommunityPluginSecretStore`; UI: `CommunityPlugin*`, `ThemeTokenResolver`, `GraphiteTheme`, `ThemeSettings` | Value types and planners stay in Core; the `URLSession` and `FileManager` parts move out (downloader to `GraphiteApple`, bridge file access to `GraphiteStorage` behind a port); secret store stays in Apple; UI and `Resources/` to `GraphitePlugins` |
| [RUNTIME](areas/runtime.md) | `Resources/CommunityPluginRuntime`: 11 scripts, 2 stylesheets, `index.html`, `Vendor`; `Tests/CommunityPluginRuntimeTests` | `GraphitePlugins/Resources`, split one object per file (Phase 9), plus `community-plugin-messages.json` |
| [ARCH](cross-cutting/architecture.md) | `App/GraphiteApp.swift`, `GraphiteDiagnostics`, `GraphiteBenchmarks` | App target (composition), `GraphiteApple` (diagnostics adapters), benchmark target |

### 3.5 Standalone packages (owner, 2026-10-20)

Code that serves Graphite but knows nothing about it lives in its own Swift package, so that it can become its own repository without a code change (decision 14, `FR-110`).

1. **What qualifies.** A component that reads or writes a format, or runs an algorithm over plain values, and that compiles without any Graphite module: it imports only Apple system frameworks (Foundation, CoreGraphics, zlib, Compression, CryptoKit) and other standalone packages. No Graphite type, preference, vault path, string-catalogue key, logger or clock appears in it; a clock or a limit it needs is a parameter.
2. **Where it lives.** `Packages/<Name>/` in this repository, with its own `Package.swift`, its own tests and fixtures (non-personal files only) and a README that states its public API and its limits. Graphite's `Package.swift` depends on it by path. Moving it to its own repository changes that one dependency from a path to a URL and a version; no Graphite code changes.
3. **How Graphite uses it.** The package returns its own values (a notebook, its pages, strokes, pictures and recordings, and a report of what it could not read); a Graphite module maps them to Graphite's documents and writes through the vault ports. A package never writes into a vault.
4. **Public surface.** `public` only for what a user of the package calls; members only tests use stay `internal` behind `@testable import` (`CC-IMPORT-16`). Each package declares its input limits (sizes, counts, nesting) in one place and refuses input past them with a typed error.
5. **Speed.** A package is compiled from source in the same build, so release builds keep whole-module and cross-module optimization across it (`FR-107`); the first extraction records its benchmarks before and after (`FR-102`).
6. **The check.** CI builds and tests each package alone (`swift build` and `swift test` with `--package-path Packages/<Name>`), and `scripts/check-imports.py` refuses any import of a Graphite module inside `Packages/`.

| Package | Contents | State |
| --- | --- | --- |
| `NotebookImport` (working name) | The Goodnotes and Notability readers and the formats under them (ZIP, binary property lists, keyed archives, protocol buffers, Apple LZ4, XML tags), the page, stroke, picture and recording planners and the import report: the 80 files of `Sources/GraphiteCore/NotebookImport` | Moved 2026-10-21 (branch `notebook-import-in-app`), as it was: the 80 files to `Packages/NotebookImport/Sources/NotebookImport`, their 31 test files and 7 fixtures to `Packages/NotebookImport/Tests/NotebookImportTests`, with its own `Package.swift` and README. `GraphiteApple` depends on it by path; CI builds and tests it alone. Its tests against real notebooks still wait for non-personal sample notebooks (`CC-IMPORT-12`). |
| Candidates | JSON Canvas reading and byte-preserving editing (`CanvasFile`, `CanvasJSON`, `CanvasChange`); the Bases formula evaluator; the Obsidian Markdown syntax scanners; the PNG and SVG ink encoders (`BandedPNGEncoder`, `SVGDrawingFile`); `ReadAloudWordAlignment` | Not checked. Each moves when the same type-check passes after its area's phase has cleaned it, and only if it is useful outside Graphite. |

## 4. Composition root and dependency injection

### 4.1 What there is today

Construction is spread over five places ([architecture 3.1](cross-cutting/architecture.md), `DIP-ARCH-01`): `GraphiteApp.init` starts two diagnostics singletons ([GraphiteApp.swift:11-14](../../App/GraphiteApp.swift#L11-L14)); `GraphiteApp.body` chooses the voice benchmark screen by a launch argument inside production code ([GraphiteApp.swift:24](../../App/GraphiteApp.swift#L24)); `GraphiteRootView` builds the workspace in a `@State` default ([GraphiteRootView.swift:8](../../Sources/GraphiteUI/GraphiteRootView.swift#L8)); `GraphiteMacScenes.init` builds another and stores it in a static weak property of the application delegate ([GraphiteMacScenes.swift:11-15](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L11-L15), [GraphiteMacScenes.swift:46](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L46)); and `WorkspaceModel`'s property initialisers build 13 collaborators (`SRP-SHELL-01`, `DIP-SHELL-01`). Because SwiftUI may build a view or scene value again, the whole construction can run again and only the first instance is kept; the audit did not settle by reading whether SwiftUI re-creates `GraphiteMacScenes` during a run, and the design depends on it not doing so (`SRP-ARCH-01`, `DIP-ARCH-01`).

### 4.2 The target

**One place builds the graph: the app target.** `GraphiteApp.init` parses `LaunchMode` (`.app`, `.voiceBenchmark`, `.hostedTests`) once from `ProcessInfo.arguments`, calls the composition for that mode and keeps the result in stored `let` properties; `body` builds one root from it and reads no flag (`FR-46`, `FR-56`).

| Piece | Where | Holds |
| --- | --- | --- |
| `AppEnvironment` (struct of constructed services) | declared in `GraphiteShell` | `ApplicationClock`, `DeviceStateStore`, `VaultLocator`, `VaultOpener`, `VaultLibrary`, `Diagnostics`, the feature services listed below, `FeatureRegistry`, the `MemoryReleasing` list |
| `LiveAppEnvironment.make()` | `App/Composition/LiveAppEnvironment.swift` | the only code that names `UserDefaults.standard`, `URLSession`, `Date`, `ContinuousClock`, the keychain and `FileManager` for app-private folders; it contains no condition beyond platform `#if` and no state |
| `HostedTestEnvironment.make(root:)` | `App/Composition/HostedTestEnvironment.swift` | the same graph over a temporary root, a private `UserDefaults` suite and a `ManualClock`: no vault restore, no diagnostics start (`T-16`, `ARCH-INV-17`) |
| `VoiceBenchmarkEnvironment.make()` | `App/Composition/VoiceBenchmarkEnvironment.swift` | the benchmark screen's services (`DIP-VOICE-05`) |
| `FeatureRegistry` | built in the app target from the registration list | document-kind descriptors, workspace commands, sidebar and inspector panel descriptors, settings pages, creation entries, Read Aloud sources, and the lists of lifecycle observers (section 9) |

The feature services in `AppEnvironment` are the process-wide objects that today are singletons or static lets: `PencilToolbox`, `PencilPreferences` source, `PencilActivity`, `PaletteCanvasMode`, `ReadingImageCache`, `ImageDecodingLimiter`, `EditorCaches`, `EmbeddedPDFSessions`, `DrawingEditorDraftStore`, `RecordingServices` (audio recorder port, video capture factory, recording store), `ReadAloudServices` (voice library, passage preparation, speech adapters, audio session owner, now-playing commands), `CommunityPluginServices` (runtime channel factory, `CommunityPluginDeviceStorage`, `HTTPDownloading`) and the theme resolver's cache location.

**The workspace is constructed once, with its environment.** `WorkspaceModel.init(environment:)` takes the environment and holds only the router state of section 6: no storage key, no I/O of its own (`FR-02`). `GraphiteApp` keeps the workspace in a `@State` initialised in `init`, so a re-evaluated view never builds a second one. On the Mac the application delegate receives a `SceneLifecycleSaver` registered by the app (an instance, not `static weak var workspaceToSave`); the saver holds the narrow capability "save everything and report failure" and nothing else, which removes the dependency behind `BUG-SHELL-03` (`SRP-SHELL-04`).

**Vault-scoped objects are built by a factory the environment owns.** `VaultOpener.open(location)` builds `VaultFiles` (with the vault's presenter, so Graphite's own writes are not reported back, `ARCH-INV-10`), the `VaultMonitor`, the `VaultIndex` (database location from `IndexLocation(cachesFolder:, clock:)`, `DIP-VAULT-02`) and `FileRecoveryStore`, and returns an `OpenVault`. The plugin host receives a capability on the same `VaultFiles`; it no longer builds a second store and a second presenter on the same vault ([CommunityPluginHost.swift:361-364](../../Sources/GraphiteUI/CommunityPluginHost.swift#L361-L364), `SRP-PLUGIN-01`, `DIP-PLUGIN-01`).

### 4.3 How views receive models

1. **Scene root.** The scene reads `WorkspaceModel` once and publishes each narrow `@Observable` model with `.environment(_:)` (`TabWorkspace`, `VaultSidebarModel`, `SearchModel`, `PresentationRouter`, `WorkspaceAlerts`, `VaultAppearanceModel`, and so on). Only the scene and the composition root store a `WorkspaceModel` (`FR-02`; today 71 stored declarations and 24 parameters take it, a baseline that only goes down).
2. **Container views** read the one feature model they show with `@Environment(Type.self)` and own a `@State` only for view-local presentation.
3. **Leaf views** take values and intent closures through the initialiser (`FR-02`). A row, preview or banner has no class-typed stored property.
4. **Services reach a model through its initialiser.** A model that needs the clock, the device store or a port takes it as an initialiser argument without a default (`FR-47`); a SwiftUI `@Environment` entry exists only for objects views read (caches, renderers, `EmbeddedContentRenderers`).
5. **No view calls a model by assigning its field.** A view calls an intent method; fields with invariants are `private(set)` (`FR-40`).

### 4.4 Previews and tests

A preview or a test builds the same graph from fakes: `AppEnvironment.fixture(...)` in `GraphiteFixtures` takes a `TemporaryVault`, an `IsolatedDeviceState`, a `ManualClock` and the in-memory ports of section 5. There is no "sample mode" flag in a production type; a sample is a composition (`FR-56`, `DIP-VOICE-05`, `DIP-INK-06`). The hosted test target launches the real app in `.hostedTests` mode and never reads the mode from a view.

### 4.5 What happens to every singleton and static service

| Today | Fate | Findings |
| --- | --- | --- |
| `MetricKitDiagnostics.shared`, `MainThreadWatchdog.shared` ([MainThreadWatchdog.swift:16](../../Sources/GraphiteApple/MainThreadWatchdog.swift#L16), [:57](../../Sources/GraphiteApple/MainThreadWatchdog.swift#L57)) | Instances built by `LiveAppEnvironment` as `Diagnostics`, started in `GraphiteApp.init` before any scene (`ARCH-INV-17`) | `DIP-ARCH-02` |
| `PDFPictureDrawingDelegate.shared` ([PDFPicture.swift:285](../../Sources/GraphiteApple/PDFPicture.swift#L285)) | Stays: a stateless delegate, listed in the allow-list file with its reason (`FR-48`) | `DIP-ARCH-02` |
| `ImageDecodingLimiter.shared` ([DrawingFileService.swift:464](../../Sources/GraphiteApple/DrawingFileService.swift#L464)) | Instance owned by `ImagePreviewService` in the environment | `DIP-ARCH-02` |
| `DocumentPlaceStore.shared` ([WorkspacePlaces.swift:80](../../Sources/GraphiteUI/WorkspacePlaces.swift#L80)) | Becomes part of `VaultDeviceMemory`, per vault, over the injected `DeviceStateStore` | `DIP-SHELL-02`, `BUG-ARCH-07` |
| `ReadingImageCache.shared` ([MarkdownPreview.swift:2651](../../Sources/GraphiteUI/MarkdownPreview.swift#L2651)) | Environment-owned cache with a named byte bound, a `MemoryReleasing` conformance and a SwiftUI environment entry | `DIP-READING-02`, `FR-72` |
| `DrawingEditorDraftStore.shared` ([DrawingEditorDraftStore.swift:70](../../Sources/GraphiteUI/DrawingEditorDraftStore.swift#L70)) | Environment-owned, directory injected; `draftIdentifiersOpenInThisProcess` ([GraphiteRootView.swift:565](../../Sources/GraphiteUI/GraphiteRootView.swift#L565)) moves into it | `DIP-ARCH-02`, `SRP-SHELL-04` |
| `PaletteToolChoiceObserver.shared` ([PencilToolPalette.swift:209](../../Sources/GraphiteUI/PencilToolPalette.swift#L209)) | `PaletteCanvasMode`, one injected instance; the notification name is kept until no other area observes it (`INK-INV-29`, `ST-25`) | `OCP-INK-02`, `DIP-INK-02` |
| `PencilToolbox.shared` ([PencilToolbox.swift:195](../../Sources/GraphiteUI/PencilToolbox.swift#L195)) | `PencilToolbox` and `PencilToolboxStore` instances in the environment; every observer names the injected instance | `DIP-INK-01`, `FR-49` |
| `CanvasPDFPageRenderer.shared` ([CanvasCardViews.swift:422](../../Sources/GraphiteUI/CanvasCardViews.swift#L422)) | Owned by `CanvasCardContentLoader` | `DIP-CANVAS-02` |
| `EmbeddedPDFSessions.shared` ([EmbeddedPDFViewer.swift:558](../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L558)) | Registry in the environment, injected per scene; no rebind on vault open ([WorkspaceModel.swift:309](../../Sources/GraphiteUI/WorkspaceModel.swift#L309)) | `DIP-LECTURE-01` |
| `ReadAloudVoices.library` and `.preparation` ([ReadAloudVoices.swift:15-17](../../Sources/GraphiteUI/ReadAloudVoices.swift#L15-L17)), `ReadAloudNowPlaying.queueCommands` | `ReadAloudServices` in the environment; the `NotificationCenter` observers of the speech adapter get a stored token and a removal (`CC-ARCH-05`) | `DIP-VOICE-01`, `DIP-VOICE-03` |
| 24 stored mutable statics (list in [architecture 8.4](cross-cutting/architecture.md)) | Each becomes an instance property of its owner (`EditorCaches`, the palm-rejection `PencilActivity`, `StrokeFootprintStore`, a `LassoPasteboard` instance) or a bounded memo in the allow-list file | `DIP-ARCH-02`, `DIP-EDITOR-01`, `DIP-INK-02` |
| `UserDefaults.standard` in 15 initialisers and static readers | One `DeviceStateStore` built by `LiveAppEnvironment`; no default argument remains | `DIP-ARCH-01`, `FR-47` |

## 5. Ports and the shape of a data source or provider

### 5.1 The ports

A port is a protocol or a struct of closures that exists because two implementations exist (production and a fake that keeps production semantics), or because a test cannot otherwise run without a window, WebKit, a database, a camera, a model, the network or the keychain (`FR-53`). Each row names its members, its implementations and the one contract suite every implementation runs (`FR-87`). Anything not listed here stays a concrete type.

| Port (declared in) | Members | Implementations | Contract suite | Findings |
| --- | --- | --- | --- | --- |
| `DocumentFileAccess` (struct of closures; Core) | 4: `read`, `save(expecting:)`, `fileExists`, `uniquePath(near:)` | Backed by `VaultFiles`; `InMemoryVaultFiles`; `FailingVaultFiles` (injects a failure per operation) | `DocumentFileAccessContractTests`: stale revision refused, vanished file, unreadable file is an error, byte order mark kept | `ISP-VAULT-01`, `ISP-EDITOR-01`, `ISP-CANVAS-04`, `ISP-BASES-01`, `LSP-VAULT-02` |
| `VaultFileManagement` (struct; Core) | 4: `move`, `duplicate`, `createFolder`, `delete(method:)`; given only to the file-management workflow | Backed by `VaultFiles`; in-memory | `VaultFileManagementContractTests`: destination exists, move into itself, trash vs delete scope | `ISP-VAULT-01`, `ISP-VAULT-02`, `FR-38` |
| `ConflictVersionDiscovery` and `ConflictVersionResolution` (Apple) | 3 and 3: `hasConflictVersions`, `conflictVersions`, `contentsLocation` read; `replaceFile`, `keepVersion`, `removeVersions` destroy ([FileVersionConflicts.swift:12-31](../../Sources/GraphiteApple/FileVersionConflicts.swift#L12-L31)) | `FileProviderConflictVersions` (macOS `NSFileVersion`, `.everyOtherVersion` for local runs); `FakeConflictVersionStore` | `ConflictVersionStoreContractTests`: stale replace, absent destination, missing version, refused coordination, failed removal | `ISP-VAULT-02`, `LSP-VAULT-02`, `LSP-ARCH-03` |
| `LinkNameTable` (Core) | 3: `paths(named:)`, `count(named:excluding:)`, `orderedPaths` | SQL table (Index); in-memory dictionary | `LinkResolutionContractTests` over one fixture vault: same lookups, same ordering, same non-ASCII folding | `LSP-VAULT-03`, `LSP-VAULT-01`, `LSP-ARCH-02` |
| `BaseRecordProvider` (Core; today non-throwing, to become throwing and kind-aware, [BaseFileRecord.swift:234-241](../../Sources/GraphiteCore/BaseFileRecord.swift#L234-L241)) | 3: `record(at:)`, `resolveLinkTarget(_:from:kind:)`, `backlinks(to:)` | `BaseIndexRecordProvider` (Index); `InMemoryBaseRecordProvider` (Fixtures, delegating name matching to the production resolver) | `BaseRecordProviderContractTests`: aliases, duplicate names, rooted and relative links, non-ASCII case, failure injection | `LSP-BASES-01`, `LSP-BASES-02`, `DIP-BASES-03` |
| `BaseRecordSource` (Bases) | 4: `baseRecord(at:)`, `baseRecords(matching:reusing:)`, `makeProvider()`, `resolve` | Index-backed (built by the shell); in-memory | Run by the provider suite over the same fixture | `ISP-BASES-01`, `DIP-BASES-01` |
| `ReadingFileLookup` (Reading) | 3: `resolve`, `isEditableDrawingPDF`, `readNote` | Vault-backed; in-memory vault | Part of `LinkResolutionContractTests` | `DIP-READING-01`, `SRP-READING-03` |
| `ApplicationClock` (Core) | 2: `now` (monotonic `Duration` since the clock's origin), `sleep(for: Duration)`; wall-clock time (`Date`) is a separate member added with its first consumer | `LiveApplicationClock` (on `ContinuousClock`); `ManualClock` in `GraphiteTestSupport` (`advance(by:)` wakes exactly the sleepers whose deadlines it reaches) | `ApplicationClockTests`: the live and manual clocks keep one contract; each advance wakes only the sleepers it reaches; a cancelled sleep throws at once | `CC-ARCH-03`, `DIP-SHELL-05`, `FR-50` |
| `HTTPDownloading` (Core) | 2: `download(_:limitBytes:)`, `streamedDownload(_:limitBytes:)` | `URLSessionHTTPDownloader` (Apple; ephemeral session, no cookies); `ScriptedHTTPDownloader` | `HTTPDownloadingContractTests`: size cap, non-success status, cancellation | `DIP-PLUGIN-02`, `DIP-BASES-04`, `DIP-VOICE-04` |
| `CommunityPluginDeviceStorage` (Plugins) | 5: consent get and set, secrets read, secrets write, remove vault | Keychain plus `DeviceStateStore`; `InMemorySecretStorage` | `CommunityPluginDeviceStorageContractTests`: not found vs failure, a failed read never leads to a write that erases other secrets | `DIP-PLUGIN-01`, `BUG-PLUGIN-05` |
| `CommunityPluginRuntimeChannel` (Plugins) | 2: `send(_:timeout:)`, `incoming` stream | WebKit page; `ScriptedRuntimeChannel` | `CommunityPluginRuntimeChannelContractTests`: order, unknown operation answered with `unknownOperation`, timeout cancels the loser | `SRP-PLUGIN-01`, `BUG-PLUGIN-01`, `BUG-PLUGIN-02` |
| `PluginEditorAccess`, `PluginFileOperations`, `PluginPresentation` (Plugins; structs of at most 7 closures each) | split from the 23 workspace members the host reads | Built by the shell; fakes | `PluginFileOperationsContractTests`: `renameFile` answers from the move outcome | `ISP-SHELL-02`, `ISP-PLUGIN-01`, `BUG-PLUGIN-03` |
| `HostChannel` (runtime JavaScript) | 2: `send`, `notify` | WebKit bridge; Node fake host | One JSON case table run by a Swift test against `CommunityPluginVaultBridge` and by a Node test against the host | `LSP-PLUGIN-01`, `LSP-RUNTIME-01`, `DIP-RUNTIME-01` |
| `ReadAloudSpeechPlayback` (Apple; replaces the 16-requirement `ReadAloudSpeaking`, whose `eventHandler` is a settable closure slot, [ReadAloudSpeech.swift:101-102](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L101-L102)) | 6: `speak`, `pause`, `resume`, `stop(scope:)`, `events` stream, `release`, plus a `capabilities` value (`supportedSpeedRange`, `appliesSystemSpeechSettings`, `reportsWordTiming`) | `AppleReadAloudSpeech`; `NeuralReadAloudSpeech`; `ScriptedSpeech` | `ReadAloudSpeechPlaybackContractTests`: event order, stale request rejected, speed range reported, route-change pause, no `.cancelled` after the adapter's own stop | `LSP-VOICE-01`, `LSP-VOICE-02`, `ISP-VOICE-01`, `BUG-VOICE-04`, `BUG-VOICE-08` |
| `ReadAloudVoiceCatalogue` (Apple) | 4: installed voices, system voice, Personal Voice request, change stream | Apple catalogue; fake | `ReadAloudVoiceCatalogueContractTests` | `SRP-VOICE-03` |
| `NeuralPassageRendering`, `ReadAloudSpeechAligning` (Voices; existing) | 2 and 1 | `MLXPassageRenderer`, `OnDeviceSpeechAlignment`; `ToneRenderer`, `EvenAligner` in Fixtures | Cancel releases the model; alignment ranges are monotonic and inside the passage | `LSP-VOICE-01`, `BUG-VOICE-07` |
| `DrawingFileFormat` (Apple) | 5: `encode`, `readRecord`, `maximumRecordBytes`, `fileExtension`, `contentType` | PNG, SVG, PDF | `DrawingFileFormatContractTests`: round trip, stale digest, corrupt record, oversize and unreadable all return the same reading enum | `OCP-INK-01`, `LSP-INK-01` |
| `LassoPictureEditing` (6 members) and `LassoCaptureSource` (5) (Ink) | as stated | `InfiniteCanvasView`, `PDFPageCanvasView`; `SelectedPicturesContent` stops stubbing five members | `LassoCanvasContentContractTests` | `ISP-INK-01`, `LSP-INK-02` |
| `PDFFileSaving` (PDF) | 5: `read`, `save(expecting:)`, `replay`, `compact`, `copy` | `PDFFileService` actor; fake | `PDFFileSavingContractTests`: conflict, vanished file, external edit | `SRP-LECTURE-02`, `LSP-ARCH-04` |
| `RecordingSession` (Recording), `AudioRecorder` (Apple), `VideoCaptureSource` (Apple; existing), `RecordingStore` (Storage) | start, pause, resume, stop, elapsed, events (6); wrap `AVAudioRecorder` and the audio session (4); existing (4); list, group, remove, all throwing (3) | `AudioRecordingSession`, `VideoRecordingSession`, fake; `ScriptedAudioRecorder`; `CameraCaptureSource`, `SyntheticCaptureSource`; file store, fake with the same errors | `RecordingSessionContractTests`, `RecordingStoreContractTests` | `OCP-LECTURE-02`, `LSP-LECTURE-03`, `LSP-LECTURE-05` |
| `TextViewEditApplier` (Editing) | 4: `apply(_:)`, `performOwnEdit`, `selection`, `viewport` | UIKit and AppKit text views | `TextViewEditApplierContractTests`: one edit is one undo step, selection mapped, viewport kept, the Mac fallback refuses and reports | `LSP-EDITOR-03`, `CC-EDITOR-03` |
| `VaultPathMoveObserver`, `VaultLifecycleObserver`, `MemoryReleasing` (Core) | 2, 2, 1 | Every store that keeps state per path, per vault or in memory | `LifecycleObserverContractTests`, parameterised over the registered observers | `OCP-ARCH-03`, `OCP-SHELL-06`, `FR-04` |
| `DocumentSession` (Core) | 6: `path`, `relocate(to:)`, `save()`, `close()`, `externalChange`, `conflict` | `MarkdownDocument`, `PDFSession`, `CanvasSession`, `BaseDocumentModel`, image and media sessions | `DocumentSessionContractTests`: save is revision-checked, a move keeps unsaved edits, close reports a failed save | `OCP-SHELL-01`, `OCP-ARCH-01`, `BUG-CANVAS-02` |

Not ports (kept concrete): `DeviceStateStore` (tests give it an isolated `UserDefaults` suite), `VaultFiles` (tests use `InMemoryVaultFiles` through `DocumentFileAccess`), `VaultIndex` (tests use a temporary database), `EditorRunLoopScheduler` and `Debouncer` (they take the clock), every view model.

### 5.2 The shape every storage or provider port follows

1. **Typed errors.** Each port has one error enum of facts, `Sendable` and equatable: `notFound(path)`, `alreadyExists(path)`, `conflict(expected:, found:)`, `tooLarge(limitBytes:)`, `refused(reason)`, `unreadable(cause)`, plus feature-specific cases. A catch-all case never stands for several failures and no case carries prose (`FR-63`, `CC-VAULT-02`).
2. **A failed read is never an empty result.** A read that can fail returns `StoredRead<Value>` with `missing`, `contents(Value, revision)` and `unreadable(error)`, or throws. Callers treat only `missing` as "use defaults" (`FR-59`, `LSP-SHELL-02`, `CC-VAULT-01`).
3. **Revision checks for writes.** A write takes the revision it read (`save(_:expecting: Revision)`) and returns `SaveOutcome` (`saved(Revision)` or `conflict(current)`); there is no overload without the expectation, and the plugin runtime's `vault.write` without one is refused ([plugin audit](areas/plugin.md), `LSP-PLUGIN-01`). `Revision` is a typed value of modification date, size and file identifier.
4. **Cancellation.** Every `async` member honours cancellation by throwing `CancellationError`; no port converts it into a value or a default.
5. **Destructive members state their scope.** Names carry the scope (`delete(method:)`, `stop(scope:)`, `removeAll(forVault:)`) and live in a separate capability from the reads (`FR-33`, `FR-38`).
6. **Results are values.** A port returns `Sendable` values with typed fields; no `[String: Any]` crosses it (`FR-44`).
7. **Providers answer one snapshot and report truncation.** An index-backed provider is created for one index version, returns bounded results (Bases: 5,000 records by default, 20,000 at most) with a `truncated` flag the UI shows, and throws `IndexLookupError` on a failed lookup instead of recording it in a side channel (`LSP-BASES-02`, section 2.6).
8. **A fake fails where production fails.** `InMemoryVaultFiles` refuses a stale revision and `FakeConflictVersionStore` requires a coordination outcome; neither makes an operation look safer (`FR-86`).

## 6. The types that replace each god object

Each table lists the new type, its single responsibility, the members it takes over and the findings that demand it. A move is two commits: first the code moves intact into the new type (the old type forwards nothing; call sites move in the same commit, `RULES.md`), then the new type is changed. Stored-property counts are those of the audits. Every new type needs a test that constructs it with plain values (`FR-96`). The order of extraction is the order of the phases in section 12.

### 6.1 `WorkspaceModel` (86 stored properties, 23 extension files; [SHELL](areas/shell.md), [ARCH](cross-cutting/architecture.md) 3.3)

| New type | Single responsibility | Members it takes over | Findings |
| --- | --- | --- | --- |
| `OpenVault` (final class, one per open vault, replaced as a unit) | The I/O handles and per-vault models of one vault | `folderAccess`, `currentVaultIdentifier`, `store` (now `VaultFiles`), `index`, `monitor`, `fileRecovery`, settings values, and the per-vault models below; every vault-scoped presentation request (`drawingEditorRequest`, `fileRecoveryRequest`, `viewedImage`, `notice`, `pathsBeingMoved`) | `SRP-SHELL-02`, `SRP-ARCH-05`, `BUG-ARCH-03` |
| `VaultSwitcher` | The ordered switch of `SHELL-INV-09` / `ARCH-INV-09`: refuse while recording, save every document and keep the vault open on failure, resolve access, build, close the old vault (plugins unload first), install | Bodies of `openVault`, `restoreVault`, `removeFromVaultList` | `SRP-SHELL-02`, `OCP-ARCH-03`, `BUG-ARCH-04` |
| `VaultDeviceMemory` | Every per-vault device key behind the registry; `forgetVault` removes all families | `expandedFolders` and `recentFiles` `didSet` persistence, `DocumentPlaceStore`, folds, tab-layout persistence | `DIP-SHELL-02`, `OCP-SHELL-06`, `BUG-SHELL-02`, `BUG-ARCH-06` |
| `VaultIndexingController` | Scan, rebuild, incremental refresh, status as a typed value | `isIndexing`, `indexingTask`, `indexingRunIdentifier`, `indexingMessage`, `pendingContentFileCount`, `isIndexScanRequestedDuringScan`, `hasCompletedIndexScan`, `indexVersion`, `refreshIndex` | `SRP-SHELL-01`, `SRP-VAULT-03`, `CC-SHELL-03` |
| `ExternalChangeCoordinator` | Debounce (500 ms settle, 2 s cap), classify with `ExternalChangeRefresh`, publish typed change events | `pendingExternalChanges`, `externalChangeTask`, `firstPendingExternalChangeInstant`, `externalRefreshDeadline` | `SRP-SHELL-01`, `DIP-SHELL-05`, `ARCH-INV-11` |
| `SearchModel` | Query, debounce, pages, sort; the focus request becomes an intent | `searchQuery`, `searchResults`, `searchContinuation`, `isLoadingMoreSearchResults`, `searchFocusRequest` | `SRP-SHELL-01`, `CC-SHELL-03` |
| `VaultFileList` | Root listing, expanded folders, reveal as an intent the sidebar observes | `rootEntries`, `expandedFolders`, `directoryVersion` | `SRP-SHELL-05`, `BUG-SHELL-04` |
| `TabWorkspace` | `TabLayout`, documents, activation, closing, history, PDF release, layout persistence through `VaultDeviceMemory` | `layout`, `layoutVaultIdentifier`, `tabDocuments`, derived `selection`, `activeTabID`, `openTabCount`, `history`, `recentFiles`, `pdfPasswords`, editor retention | `SRP-SHELL-01`, `OCP-SHELL-01`, `OCP-ARCH-01` |
| `FileOperationsModel` | Move, rename, copy, delete and the link-update question queue; fan-out is `VaultPathMoveObserver` conformances | `pendingMove`, `pendingDeletion`, `fileSheet`, `pathsBeingMoved`, the 8-store fan-out at [WorkspaceModel.swift:1201-1222](../../Sources/GraphiteUI/WorkspaceModel.swift#L1201-L1222) | `OCP-ARCH-03`, `BUG-CANVAS-02` |
| `NoteCreation`, `AttachmentPublisher`, `DrawingWorkflow`, `RecordingWorkflow` | One write workflow each; every write ends with one `afterWrite(paths:)` call | Creation, paste, drawing and recording methods; `drawingEditorRequest`, `noteTextWhenDrawingBegan`, a `FolderAccess` captured at start (as recording does with `recordingFolderAccess`), `recordingNotePath`, `recordingRecoveryOffer`; `RecordingWorkflow` owns the "stop Read Aloud" rule once | `SRP-SHELL-01`, `BUG-ARCH-03` |
| `ConflictVersionTracker`, `FileRecoveryModel`, `VaultAppearanceModel` (with theme), `BookmarksModel` | The existing extension files, each given its own state | `conflictedPaths`, `pendingConflictChecks`, `conflictCheckTask`, `fileRecoveryRequest`; `vaultAppearance`, `noteTypography`, `noteTheme`, `themeRefreshTask`, `lastThemeInputs`, `pendingAppearanceSave`; `bookmarks` | `SRP-ARCH-01`, `LSP-VAULT-02` |
| `VaultGraphProvider` (`GraphiteGraphAndMap`) | Graph, positions and placed notes per vault, keyed by index identity and version | `graphCache`, `graphPositions`, `placedNotesCache`, `isGraphPresented`, `isMapPresented` | `OCP-CANVAS-03`, `BUG-CANVAS-06` |
| `WorkspaceAlerts` and `PresentationRouter` | A queue of typed alerts and notices with one presenter; one `PresentedScreen` enum for the 14 sheets, covers and alerts | `errorMessage`, `notice`, and the presentation booleans of `GraphiteRootView` | `SRP-SHELL-03`, `SRP-ARCH-04`, `CC-ARCH-01` |
| `WorkspaceWindowLayout` | Columns, compact column, inspector, focus mode, active palette | 14 `@State` values of the root view, `WindowActions` | `SRP-SHELL-04`, `ISP-SHELL-04` |
| `SceneLifecycleSaver` | Remember places, save, keep alive in the background, Mac quit with one policy for a failed save | [GraphiteRootView.swift:227-238](../../Sources/GraphiteUI/GraphiteRootView.swift#L227-L238), the quit reply at [GraphiteMacScenes.swift:49-63](../../Sources/GraphiteUI/GraphiteMacScenes.swift#L49-L63) | `BUG-SHELL-03`, `SRP-SHELL-04` |
| `WorkspaceCommandCatalogue` | Each command declared once (section 8) | `WorkspaceCommandList`, `GraphiteCommands` | `OCP-SHELL-02`, `OCP-ARCH-02` |
| `PluginEditorAccess`, `PluginFileOperations`, `PluginPresentation` | The plugin host's workspace capabilities, at most 7 members each | The about 23 workspace members the host reads | `ISP-SHELL-02`, `SRP-PLUGIN-04` |
| `WorkspaceModel` (remaining) | Router: holds the types above, routes UI events | no storage key, no I/O; at most 15 stored properties | `SRP-SHELL-01`, `SRP-ARCH-01`, `FR-01`, `FR-02` |

`GraphitePreferences` (36 stored properties, nine feature areas, eight unrelated concepts in one file; `SRP-SHELL-06`) splits into `EditorPreferences`, `AppearancePreferences`, `DrawingPreferences`, `RecordingPreferences`, `SearchPreferences`, `RecoveryPreferences`, `CorePluginPreferences` and `CommandPalettePreferences`, each over the typed registry of section 7 (`FR-15`). `GraphiteRootView` (14 `@State` values, one 172-line `body`) keeps composition only; `CreateDocumentSheet` and the paper presets move to files named after them, and drawing-draft recovery moves into the Ink feature as `DrawingDraftRecovery` (`SRP-SHELL-04`, `CC-SHELL-01`).

### 6.2 The note editor and the reading view ([EDITOR](areas/editor.md), [READING](areas/reading.md), [MDCORE](areas/mdcore.md))

| New type | Single responsibility | Members it takes over | Findings |
| --- | --- | --- | --- |
| `Coordinator` (iPad, Mac; at most 10 stored properties) | Delegate adapter: routes each UIKit or AppKit callback to one collaborator | Today 47 stored properties and 16 kinds of work in [NativeMarkdownEditor.swift:771-2325](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L771-L2325) | `SRP-EDITOR-01`, `SRP-EDITOR-04` |
| `NoteEditorInputs` (Equatable value) | Everything the pane passes to the editor, so `update` works only on change | The 25-member environment and the `EditorActions` 14-closure bag | `ISP-EDITOR-02`, `ISP-EDITOR-04`, `CC-EDITOR-08` |
| `NoteEditorSessionDuties` | Report place, drain `NoteEditorRequest`s, take the start location, mark the cursor placed, report typing; one implementation for both coordinators | `reportPlace`, `startEditingIfRequested`, `presentFindIfRequested`, `goToReadingPlaceIfSwitched`, `hasPlacedCursor`, `isTyping` | `LSP-EDITOR-01`, `LSP-EDITOR-06`, `BUG-EDITOR-01` to `BUG-EDITOR-04` |
| `EditorHostingLifetime<HostedView>` | Make, dismantle, suspend, resume, discard; container hand-over | The two diverging suspend paths | `LSP-EDITOR-02` |
| `TextViewEditApplier` (protocol, UIKit and AppKit) | Apply a `MarkdownTextEdit` as one undo step, mapping selection and keeping the viewport | `isPerformingEdit`, `isApplyingOwnEdit`, the Mac `replaceText` fallback that sets `string` | `LSP-EDITOR-03`, `CC-EDITOR-03` |
| `InsertionApplier`, `PastedContentClassifier`, `PastedContentImporter`, `PastedImagePolicy` | Re-target queued insertions; decide what a paste is; load and encode; one image-format rule | The paste and drop pipeline of the iPad text view | `SRP-EDITOR-03`, `LSP-EDITOR-05` |
| `NoteFoldingState`, `FoldButtonOverlay` | Fold regions across edits; chevrons | Fold state in the coordinator | `SRP-EDITOR-01` |
| `RenderedBlockPlacementScheduler`, `EditorJumpController`, `EditorTapTargets`, `SuggestionRevisionTracker` | Placement budgets; `Jump` decisions; link and checkbox under a character; revision of accepted suggestions | The matching coordinator clusters (about 14 duplicated iPad and Mac function pairs) | `CC-EDITOR-04`, `CC-EDITOR-02` |
| `EditorRunLoopScheduler` | The one primitive for "after this update, after layout, after a delay": owned, coalesced, cancelled on suspend | 21 main-queue hops and a 250 ms sleep | `CC-EDITOR-02`, `FR-65` |
| `EditorCommandDescriptor` list | Title, symbol, shortcut and surfaces per `EditorCommand` | Seven parallel command sites | `OCP-EDITOR-02`, `FR-23` |
| `LivePreviewBlockKindTraits` | Key name, index reading, memory and height estimate, Read Aloud support per block kind | Five parallel switches and the `default:` in `hasReadingSession` | `OCP-EDITOR-01`, `FR-19` |
| `EditorCaches` | Measured heights, math metrics, math images, embed locations, with memory-warning and vault-switch duties | Six static mutable caches | `DIP-EDITOR-01`, `FR-72` |
| `MarkdownDocument`, `NoteInsertionQueue`, `NoteViewState`, `NoteEditorRequests` | Persistence over `DocumentFileAccess`, queued insertions, view state, UI requests | `MarkdownSession` (mixes five concerns; holds the whole store to use five operations) | `SRP-EDITOR-02`, `ISP-EDITOR-01` |
| `ReadingViewBuilder` (own file, `BuildState` value), `ReadingBuildModel`, `ReadingScrollRestoration`, `ReadingWordFollower`, `ReadingBlocksView` and one view per block kind | Build, schedule, restore scroll, follow Read Aloud, draw | `MarkdownPreview` (seven jobs, 37 stored properties, 127-line `body`; 64 types in one file) | `SRP-READING-01`, `SRP-READING-02`, `SRP-READING-03`, `OCP-READING-01` |
| `NoteTextEditor`, `NoteAutosave`, `NoteLinksInspectorModel` | Apply an edit to an open or closed note with an explicit save policy and a typed `NoteEditOutcome`; save after a pause for every session with changes; outline, links, tags, footnotes, mentions with latest-answer-wins | Three implementations of "edit a note, open or closed"; autosave in invisible background views | `SRP-READING-05`, `SRP-READING-06`, `SRP-READING-07`, `BUG-READING-04` |
| `NoteToolbar`, `NoteReadAloudCommands`, `NoteAttachmentImport` | Pane parts that receive narrow values | `MarkdownPane` (toolbar, menus, imports, Read Aloud rules, editor wiring) | `SRP-READING-04`, `ISP-READING-01` |
| `MarkdownLineSyntax` (one file per concept), `MarkdownInlineSyntax`, `MarkdownBlockLines`, `SortedRangeSet`, `BoundedMarkdownParser`, `StaticPattern` | The one answer to "what is this line", inline facts, per-line context, overlap queries, the only parser entry, constant patterns | `MarkdownEditing` line rules, `CodeFence`, the private fence and table copies in `TextColorMarkup`, `NoteBlocks`, `Footnotes`, `LivePreviewBlockScanner`, `NotePreviewDocument`; the 5 `Document(parsing:)` sites; 53 `try?` patterns | `LSP-MDCORE-01`, `SRP-MDCORE-03`, `SRP-MDCORE-05`, `OCP-MDCORE-03`, `CC-MDCORE-01`, `CC-MDCORE-09` |
| `ReadingMarkers`, `ObsidianComments`, `ReadingMathPreparation`, `ReadingInlineMarking`; `HTMLTokenScanner`, `HTMLEntityDecoder`, `MarkdownLineWriter` (with a `LinePosition` enum), `InlineDelimiterStack` | The pieces of `ObsidianInlineMarkup` (11 duties) and of `HTMLToMarkdown.Converter` (four position flags written at 28 sites) | as named in [MDCORE](areas/mdcore.md) 7.1 | `SRP-MDCORE-01`, `SRP-MDCORE-02`, `BUG-MDCORE-06` |

### 6.3 PDF, recording and Read Aloud ([LECTURE](areas/lecture.md), [VOICE](areas/voice.md))

| New type | Single responsibility | Members it takes over | Findings |
| --- | --- | --- | --- |
| `PDFAnnotationCoordinator` (overlay provider and wiring only) with `PDFPageCanvasPool`, `PDFToolPaletteController`, `PDFTouchRouting`, `PDFTextMarkupInteraction`, `PDFReadAloudPenOverlay`, `PDFCanvasRepair`, `PDFInkRecorder` | One each of the 13 responsibilities and 37 stored properties of [GraphitePDFView.swift:739-1696](../../Sources/GraphiteUI/GraphitePDFView.swift#L739-L1696); repairs become a typed enum | Canvas pool, ink recording, tool palette, first responder, gesture routing, text markup, repair | `SRP-LECTURE-01`, `SRP-LECTURE-07`, `CC-LECTURE-13` |
| `PDFDocumentEditor`, `PDFSaveController`, `PDFProtection`, `PDFEditHistory`, `PDFViewState`, `PDFOutlineModel` | The parts of `PDFSession` (46 stored properties across 4 files): live document and edits; baseline, revision, autosave, conflicts; password, permissions, signatures; undo; page in view and selection; outline | As mapped in [LECTURE](areas/lecture.md) 3.2 | `SRP-LECTURE-02`, `ISP-LECTURE-04`, `LSP-ARCH-04` |
| `PDFEdit` (own file), `PDFAnnotationKey` (`CaseIterable`), `PDFEditApplier`, `PDFPageExport`, `PDFFileService`, `PDFSignatureInspection` | Split of the six-concern `PDFPageManager.swift`; one signature rule | The edit vocabulary, key registry, edit application, export, destinations, file actor | `SRP-LECTURE-06`, `OCP-LECTURE-01`, `OCP-LECTURE-03`, `LSP-LECTURE-01` |
| `EmbeddedPDFViewerModel` | An embed's load, release, claim and conflict state | Saving, reloading and session lifecycle inside `EmbeddedPDFViewer` | `SRP-LECTURE-04`, `BUG-LECTURE-02` |
| `RecordingFlow` (enum), `AudioRecordingSession`, `VideoRecordingSession`, `RecordingPublisher`, `RecordingRecoveryInventory` with `RecordingStore`, `RecordingMessagePresenter` | One recording state with associated values; one media kind each; convert, join and publish atomically; throwing listings; typed reasons to words | `RecordingController` (26 stored properties; audio, video, publication, recovery) | `SRP-LECTURE-03`, `OCP-LECTURE-02`, `CC-LECTURE-07`, `BUG-LECTURE-01` |
| `ReadAloudTransport` and `ReadAloudStatus` | Every user intent (play, pause, `stop(scope:)`, sentence, section, speed) and the read-only projection views show | The 67 `reader.session.…` call sites and four `stop` functions | `ISP-VOICE-02`, `LSP-VOICE-03`, `BUG-VOICE-01` |
| `MarkdownReading`, `PDFReading`, `ScannedPageReview`, `FollowReadingPolicy` | One kind of reading each, owning its tasks | `ReadAloudController` (39 stored properties; every source and concern) | `SRP-VOICE-01`, `CC-VOICE-02` |
| `ReadAloudPlaybackState` (Core), `ReadAloudPlayback`, `ReadAloudVoiceSelection`, `ReadAloudSpeechSettings`, `ReadAloudAudioSessionOwner` | The playback enum and pure transitions; driving a `ReadAloudSpeechPlayback`; voice choice; speed and highlight; the one audio session shared by both adapters | `ReadAloudSession` (24 stored properties) | `SRP-VOICE-03`, `CC-VOICE-12`, `CC-VOICE-07`, `BUG-VOICE-03` |
| `ListeningQueue`, `RememberedReadingPlaces` (per vault), `ReadAloudPenSelection`, `ReadAloudLayoutFrames` | Navigator pieces | `ReadAloudNavigator` (19 stored properties) | `SRP-VOICE-04`, `BUG-ARCH-07` |
| `PassageRenderQueue` (Core value), `CheckedPassageRenderer` | Queue, ready set and waiters with pure transitions; attempts and checks | `ReadAloudPassagePreparation` (scheduler, retry policy and status in one object) | `SRP-VOICE-05`, `CC-VOICE-14` |
| `MarkdownNarrationMasking`, `MarkdownNarrationLeaves`, `NarrationAssembler`, `TextRunSourceMapper`, `PDFPageLines`, `RunningTextFilter`, `HyphenationJoiner`, `SpokenReplacements` | One step of narration each | `ReadAloudDocument.markdown` (273 lines) and `pageText` (149) | `SRP-VOICE-02` |

### 6.4 Plugins ([PLUGIN](areas/plugin.md), [RUNTIME](areas/runtime.md))

| New type | Single responsibility | Members it takes over | Findings |
| --- | --- | --- | --- |
| `CommunityPluginSession` | One open vault's plugin runtime, created at vault open, released at close; holds `CommunityPluginRuntimePhase` | `CommunityPluginHost`'s lifecycle booleans `isRuntimeRunning`, `isPageLoaded`, `pageLoadFailure` and identity checks | `SRP-PLUGIN-01`, `CC-PLUGIN-01`, `BUG-PLUGIN-01` |
| `CommunityPluginRuntimeConnection` (behind `CommunityPluginRuntimeChannel`) | WebKit page, page load, timeouts, typed send and receive | `WKWebViewConfiguration` construction, `send(_:timeout:)` | `DIP-PLUGIN-01`, `CC-PLUGIN-03` |
| `CommunityPluginContributions` | What plugins registered, one `Decodable` value replaced whole | The per-capability fields reset by hand (35 fields, 13 missed) | `SRP-PLUGIN-02`, `OCP-PLUGIN-02` |
| `CommunityPluginPackages`, `CommunityPluginEditorBridge`, `CommunityPluginSurfaces`, `CommunityPluginViewRegistry`, `CommunityPluginCopyCache`, `CommunityPluginPageStyles` | Inventory, consent, install outcomes; snapshots and plugin edits; notices and menus; views and restore state (the only writer of plugin view state); shown copies and their LRU; page styles and theme push | The remaining parts of the host (63 stored properties) and the `WorkspaceModel` extension that writes host state | `SRP-PLUGIN-01`, `SRP-PLUGIN-04`, `BUG-PLUGIN-06` |
| `CommunityPluginHostOperation`, `CommunityPluginRuntimeOperation`, `CommunityPluginFailureKind`, typed message payloads | The 83 operation names (44 JavaScript to Swift, 39 Swift to JavaScript) and 16 failure kinds as enums generated from `community-plugin-messages.json` | Three parallel `switch`es and untyped `[String: Any]` payloads | `OCP-PLUGIN-01`, `ISP-PLUGIN-03`, `CC-PLUGIN-05` |
| Runtime scripts: `host-channel.js`, `host-message-router.js`, `coalesced-notifier.js`, `plugin-attribution.js`, `vault-tree.js`, `data-adapter.js`, `path-write-queue.js`, `snapshot-editor.js`, `leaf-host-state.js`, `listener-marking.js` and the files of [RUNTIME](areas/runtime.md) 3.2 and 3.5 | One object per file, collaborators passed at construction, handlers registered through the router | `plugins.js` (1324 code lines, about 18 responsibilities), `reading.js`, the global `GraphitePluginRuntime` registry | `SRP-RUNTIME-01`, `SRP-RUNTIME-02`, `SRP-RUNTIME-03`, `OCP-RUNTIME-03` |

### 6.5 Ink, canvas and Bases ([INK](areas/ink.md), [CANVAS](areas/canvas.md), [BASES](areas/bases.md))

| New type | Single responsibility | Members it takes over | Findings |
| --- | --- | --- | --- |
| `HistoryCanvasView` (history only) with `CanvasToolBinding`, `EvenHighlightStroke`, `HeldShapeTracker`, `RenderCover`, `HandStrokeTakeBack`, `CanvasMode` | A `PKCanvasView` subclass that records history and nothing else; one tool-mode enum | Nine jobs and 35 plus 2 static stored properties inherited by every canvas | `SRP-INK-01`, `OCP-INK-02`, `BUG-INK-02` |
| `InkSelectionController` (wiring), `InkSelectionState`, `InkSelectionEdits`, `InkSelectionMenu` (typed actions) | Wiring; state value; pure edits; menu and VoiceOver actions from typed actions | The 21-property controller (gestures, rendering, stroke editing, pasteboard, capture, menus); dispatch on menu titles | `SRP-INK-02`, `OCP-INK-03`, `CC-INK-05` |
| `DrawingEditorSession`, `DrawingPictureArrangement`, `DrawingPictureLayerView`, `InfiniteCanvasView` (zoom and taps) | Save, close, export, draft, alert enum; picture arrangement as one operation at a time; picture and paper rendering | `DrawingCanvasController` (history, arrangement, paper, error reporting, 18 manual projection calls) and the `DrawingEditor` view's file and pasteboard work | `SRP-INK-03`, `SRP-INK-04`, `SRP-INK-05`, `BUG-INK-03` |
| `PencilToolbox` with `PencilToolboxStore`, `PencilPreferences`, `PaletteCanvasMode`, `PencilActivity` | Bar state, tolerant persistence, one observed preference value, one palette mode, one activity per process | `PencilToolbox.shared`, the `UserDefaults` reads in touch code | `DIP-INK-01`, `DIP-INK-03`, `CC-INK-07` |
| `CanvasDocument`, `CanvasDocumentPersistence`, `CanvasViewportModel`, `CanvasSelection`, `CanvasGesture` with `CanvasInteractionModel`, `CanvasCommands`, `CanvasCardContentLoader` | File, history and the text being typed; autosave and conflicts over `DocumentFileAccess`; viewport and level of detail; selection; gesture state machine; selection to changes; card content as typed results | `CanvasSession` (34 stored properties, 8 responsibilities), card views' file I/O | `SRP-CANVAS-01`, `SRP-CANVAS-03`, `CC-CANVAS-01`, `BUG-CANVAS-01`, `BUG-CANVAS-02` |
| `BaseRecordLookup`, `BaseFormulaTable`, `BaseValueOperators`, `BaseFunctionLibrary` (keyed by `BaseFunctionName`), method libraries by receiver (keyed by `BaseMethodName`), `JavaScriptText` | Per-run link-identity memo; formula memo and cycle detection; operator semantics; the 16 global functions; the 6 method families; JavaScript string and number semantics | The 1,005-code-line `BaseEvaluator` keeps only `evaluate`, scope and the depth guard | `SRP-BASES-01`, `OCP-BASES-01`, `OCP-BASES-03`, `SRP-BASES-03` |
| `BaseDefinitionFile`, `BaseViewSelection`, `BaseQueryRun`, `BaseNotePropertyWriter`, `BaseDocumentModel` (published state and one intent per UI event) | Definition read, edit and save; selected view and sort; query off the main actor with latest-answer-wins; serialised property writes | `BaseDocumentModel` (28 stored properties, five workflows, one error field) | `SRP-BASES-02`, `ISP-BASES-02`, `CC-BASES-02` |

### 6.6 Vault and index ([VAULT](areas/vault.md))

| New type | Single responsibility | Members it takes over | Findings |
| --- | --- | --- | --- |
| `VaultFiles` (actor), `VaultFileManagement`, `FreeFileName`, `ObsidianConfigurationFile` (enum), `ObsidianJSONObjectFile`, `ObsidianConfigurationFiles`, `ObsidianSettingsStore` | Read, save, exists, list; move, duplicate, delete; pure naming; one case per `.obsidian` file; member-preserving JSON; read state `missing`, `contents`, `unreadable`; baselines travel in the read result | `VaultStore` (32 methods: I/O, management, naming policy, six settings files) | `SRP-VAULT-01`, `OCP-VAULT-02`, `CC-VAULT-01`, `BUG-VAULT-02` |
| `IndexDatabase`, `IndexSchemaMigrations`, `IndexLocation`, `IndexRowWriter`, `VaultScanner` (with `ScanPhase`), `LinkIndexQueries` over `LinkNameTable`, `IndexSearch`, `QuickSwitcherQueries`, `TagAndPropertyQueries`, `GraphQueries`, `PlacedNoteQueries` | Connection and schema; cache placement; row writes; scan state; one query family each | `VaultIndex` (600 code lines; schema, placement, scanning, refresh, five query families), the scan's boolean, optional and dictionary | `SRP-VAULT-02`, `SRP-VAULT-03`, `SRP-VAULT-05`, `LSP-VAULT-03`, `DIP-VAULT-02` |
| `FrontmatterLocator`, `VaultLinkResolution`, `MediaClassification` (merged into `DocumentKind`), `FileURLToVaultPath` | The one frontmatter rule (4 regular expressions today), the one link resolver (four to five implementations), the one media vocabulary, the one URL-to-path conversion (written seven times) | Copies named in `CC-VAULT-03`, `LSP-ARCH-02`, `LSP-ARCH-01`, `CC-ARCH-08` | `CC-VAULT-03`, `LSP-ARCH-01`, `LSP-ARCH-02`, `CC-ARCH-08`, `BUG-ARCH-01` |

## 7. State ownership

### 7.1 One owner per fact

| Lifetime | Owner | Holds |
| --- | --- | --- |
| Process | `AppEnvironment` services | Clock, device-state store, diagnostics, process-wide caches (each with a named bound and a `MemoryReleasing` conformance), the Pencil toolbox and its activity, voice library and render queue, the feature registry |
| Window (scene) | `WorkspaceModel` router, `WorkspaceWindowLayout`, `PresentationRouter`, `WorkspaceAlerts`, `SceneLifecycleSaver`, the embedded-PDF session registry | Presentation state, columns, inspector, the alert queue; one workspace per window, several windows per process since the scene split of decision 12 landed (2026-10-21; `ARCH-INV-08` retired) |
| Vault | `OpenVault` and the models that conform to `VaultLifecycleObserver` | I/O handles, index, tabs, search, file list, conflict and recovery state, appearance, bookmarks, graph and map caches, plugin session, the vault's device memory |
| Document | The `DocumentSession` of one tab | Text or document, revision, undo history, place, pending insertions, conflict |
| View | `@State` | Presentation-only values that no other object reads (a focus ring, a popover flag, a drag in progress) |

Rules: a fact has one owner and every other holder reads a projection (`FR-13`); per-vault facts are enumerable so removing a vault is one call (`FR-04`, `FR-73`); a view never keeps a copy of controller state (`SRP-INK-03`, `SRP-VAULT-01`); a flow with more than two states is an enum (`FR-11`).

### 7.2 The typed registry of persisted keys

Every key below keeps its exact name, value type, encoding and default; the registry may move declarations and may not change any of them (`ARCH-INV-01`, `ST-01` to `ST-27`). Each key is declared once as a `DeviceStateKey` and read and written only through `DeviceStateStore` over an injected `UserDefaults`. Scope: G is the device, V is per vault (`<name>.<UUID.uuidString>`, upper-case and hyphenated). Version: all keys are unversioned today except `GraphitePencilToolbox.v2`; the registry records `version: 1` for them and bumps only with a decoder for the old form.

| Key or key family | Owner after the cleanup | Default | Scope | Encoding | Invariants |
| --- | --- | --- | --- | --- | --- |
| `GraphiteDefaultNoteView`, `GraphiteDefaultEditingMode`, `GraphiteUsesReadableLineLength`, `GraphiteUsesSpellChecking`, `GraphiteFormatsCodeBlocks`, `GraphiteShowsInlineTitle`, `GraphiteShowsFileExtensions`, legacy read-only `GraphiteTextSize` | `EditorPreferences` | `editing` note view, `livePreview` editing mode, readable line length true; absent or unknown reads as the default | G | String raw value (`editing`/`reading`, `livePreview`/`source`), Bool, Double 12 to 28 | `ST-01` to `ST-03` |
| `GraphiteAppearanceMode`, `GraphiteAccentColor`, `GraphiteUsesVaultTheme`, `GraphiteColorPalette`, `GraphiteHighlighterPalette` | `AppearancePreferences` | `system` appearance; accent resolved device, then vault, then default | G | String raw value; canonical hex; JSON `[PaletteColor]` (`id`, `name`, `hex`) | `ST-01`, `ST-04`, `ST-05` |
| `GraphiteDrawingFormat`, `GraphiteDrawingBackground`, `GraphiteDrawingPaperPattern`, `…PaperSpacing`, `…PaperLineColor`, `…PaperLineStrength`, `GraphiteNotebookPaperColor`, `…LineColor`, `…LineStrength`, `…PaperSpacing`, `GraphiteDrawsOnPencilDoubleTap`, `GraphiteDrawingPaperAppearsInNotes` | `DrawingPreferences` | Documented default; transparent notebook paper reads as white | G | String raw value (`png`/`pdf`/`svg`), Bool, Double within `NotebookPaperSpacing.choices` | `ST-01` to `ST-03` |
| `GraphiteRecordingCamera`, `GraphiteEmbedsRecordingsInNote` | `RecordingPreferences` | Documented default | G | String raw value, Bool | `ST-01`, `ST-02` |
| `GraphiteSearchSortOrder` | `SearchPreferences` | `fileNameAscending` | G | String raw value of six cases | `ST-01` |
| `GraphiteSnapshotIntervalMinutes`, `GraphiteSnapshotHistoryDays` | `RecoveryPreferences` | 5 (1 to 60), 7 (1 to 365); out-of-range, zero and absent give the default | G | Int | `ST-03` |
| `GraphiteDisabledCorePlugins`, `GraphiteEnabledCorePlugins` (2026-10-19), `GraphiteRecentCommands` | `CorePluginPreferences`, `CommandPalettePreferences` | empty; an absent `GraphiteEnabledCorePlugins` runs the one-time Read Aloud migration | G | `[String]` of sorted `CorePlugin` raw values; command identifiers, most recent first | `ST-04`, `ST-06`, `ARCH-INV-07` |
| `GraphiteMakesShapesOnHold`, `GraphiteHighlighterIgnoresTilt`, `GraphitePalmRejection`, `GraphitePencilToolbarStyle`, `GraphiteLassoShape`, `GraphiteLaserPointerStyle`, `GraphiteDrawingDrawsWithFinger`, `GraphiteDrawsShapes` (shared with PDF) | `PencilPreferences` | on, off, on, `floating`, `freehand`, `dot`, off, off | G | Bool or String raw value | `ST-08`, `ST-10` |
| `GraphitePencilToolbox.v2` | `PencilToolboxStore` | empty toolbox | G | Data, JSON `StoredState` (`toolInUse`, `presets` at most 6, `presetInUseIndex`, `erasesWholeStrokes`, `eraserWidth`, optional `eraserWidthChoices`); the only versioned key; tolerant: an unknown ink keeps the other presets | `ST-09`, `CC-INK-07` |
| `GraphitePDFDrawsWithFinger`, `GraphitePDFShowsToolPicker`, `GraphitePDFWritingGuidePattern`, `GraphitePDFWritingGuideSpacing` | `PDFPreferences` | Documented default | G | Bool or String raw value | `ST-10` |
| `GraphiteCanvasSnapsToGrid`, `GraphiteCanvasSnapsToObjects` | `CanvasPreferences` | true, true | G | Bool | `ST-11` |
| 15 unprefixed keys `graphShows…`, `graphLinkDistance`, `graphRepelStrength`, `graphCenterStrength`, `localGraph…` | `GraphSettings` | Declared at the `@AppStorage` sites today; copied into the registry unchanged | G | Bool, Double, Int | `ST-11` |
| `sidebarPanel`, `tagsViewSortOrder`, `tagsViewShowsNestedTags`, `propertiesViewSortOrder`, `GraphiteInspectorPanel`, `GraphiteShowsUnlinkedMentions` | `SidebarPreferences`; written only by their owner, never by a command (`FR-74`) | `files`; `outline` | G | String raw value, Bool | `ST-07`, `DIP-ARCH-04` |
| `GraphiteReadAloudVoiceChoice`, `…HighlightMode`, `…Speed`, `…NeuralVoice`, `…QualityMode`, `…ReadsUnpreparedPassagesQuickly`, `…PlayerCorner`, `…TapHintShown`, `…FloatingPlayer`, `readAloudMathematicalStyle`, `readAloudPDFReadingOrder`; suite `com.graphite.study.readAloudSample` | `ReadAloudPreferenceKey` | Highlight `words` (others `sentences`, `off`), speed 0.5 to 3 with the default set by the session, floating player true | G | JSON `{identifier, source}` at most 4,096 bytes, String raw value, Double, Bool | `ST-12`, `ST-13` |
| `GraphiteReadAloudPositions`, `GraphiteReadAloudPositionsOrder` | `RememberedReadingPlaces` | empty, cap 300 | G today; V after the fix: the corrected key is new, the old global keys are read once and dropped | `[String: Int]`, `[String]` | `ST-14`, `ST-15`, `BUG-ARCH-07` |
| `GraphiteKnownVaults`, `GraphiteKnownVaults.unreadable`, legacy `GraphiteVaultBookmark` | `VaultLibrary` | empty list | G | Data, default `JSONEncoder` JSON; undecodable entries written back unchanged; an undecodable list kept under `.unreadable` | `ST-16`, `VAULT-INV-24` |
| `GraphiteExpandedFolders.<UUID>`, `GraphiteRecentFiles.<UUID>` | `VaultDeviceMemory` | empty | V | `[String]` of vault paths (sorted; most recent first) | `ST-18` |
| `GraphiteTabLayout.<UUID>` | `VaultDeviceMemory` over `TabLayout` | empty layout | V | Data, JSON `SavedTabLayout`; restore drops missing and repeated files, keeps at most 2 groups, clamps the split to 0.25 to 0.75 | `ST-19`, `VAULT-INV-25` |
| `GraphiteDocumentPlaces.<UUID>` | `VaultDeviceMemory` | empty, at most 400 | V | Data, JSON `DocumentPlaceMemory` with default date encoding (seconds since 2001) | `ST-20`, `NM-10` |
| `GraphiteFolds.<UUID>` | `VaultDeviceMemory` | empty | V | `[String: [String]]`, path to sorted fold keys; removed with the vault (today it is not, `BUG-ARCH-06`) | `ST-21`, `ST-22` |
| `GraphiteCommunityPluginsTurnedOn.<UUID>` | `CommunityPluginDeviceStorage` | false | V | Bool | `ST-23` |
| Notification names `GraphitePencilToolboxSelectionDidChange`, `GraphitePaletteInkSelectionDidChange`, `GraphitePDFSessionPicturesDidChange` | `PencilToolbox`, `PaletteCanvasMode`, `PDFSession` (typed; removed when no observer remains) | n/a | process | string pinned by a test | `ST-25` |

Removing a vault removes every V family through `deviceState.removeAll(forVault:)`; the removal test enumerates the registry, not a list in the test (`ST-24`, `FR-73`).

### 7.3 Files, folders, identifiers and embedded formats

| Fact | Owner | Declaration |
| --- | --- | --- |
| App-private folders: `Application Support/Graphite/File Recovery`, `…/Graphite/Recovery/Recordings`, `Application Support/Drawing Drafts/<UUID>.svg` and `.json`, `Application Support/Voices/<voice id>` (excluded from backup), `Caches/Graphite/Indexes/<vault UUID>.sqlite` with `-wal` and `-shm`, `Caches/Graphite/ThemeTokens`, `Caches/ReadAloudAudio` with `index.json`, `Library/Diagnostics` (at most 80 files), temporary `Graphite-OpenPDF-*`, `Graphite Exports` | `ApplicationFolders` in `GraphiteStorage`, one case per folder with its parent kind (Application Support, Caches, Library, temporary) | Typed; a path-registry test compares each case with the literals of `ARCH-INV-03`, `ST-26` |
| Vault files Graphite owns or edits: `.obsidian/app.json`, `appearance.json`, `bookmarks.json`, `types.json`, `templates.json`, `daily-notes.json`, `community-plugins.json`, `themes/<name>/theme.css`, `snippets/<name>.css`, `plugins/<id>/{main.js,manifest.json,styles.css,data.json}`, `.graphite/pronunciations.json` | `ObsidianConfigurationFile` (enum, one case per file with its owned keys) and `GraphiteVaultFile` for `.graphite/…` | Typed; each has one `Codable` type for read and write (`FR-44`), golden fixtures (`FR-95`), `OB-01` to `OB-17` |
| Keychain item: service `Graphite community plugin secrets`, account the vault `uuidString`, value JSON `[String: String]`, accessibility after-first-unlock this-device-only, at most 1 MiB | `CommunityPluginDeviceStorage` | Constants in one enum; `ARCH-INV-04` |
| Web storage: one `WKWebsiteDataStore` per vault identifier, removed with the vault | `CommunityPluginSession` | `ARCH-INV-05`, `ST-27` |
| External identifiers: bundle `com.graphite.study`, URL scheme `graphite`, UTTypes `com.graphite.study.vault-item`, `.tab`, `.pdf-page`, background session `com.graphite.study.voice-downloads`, log subsystem `com.graphite.study`, share activity `com.graphite.study.addToNote` | `ExternalIdentifiers` (Core) | A test reads `Info.plist` and compares (`ARCH-INV-06`, `EX-01`, `EX-07`) |
| In-file identifiers: `GraphitePencilDrawingV1`, `GraphitePictureV1` and `V2` and the other PDF annotation keys; the PNG chunk `grPK`; SVG `graphite-drawing` metadata with `urn:graphite:drawing:1`; attribute keys shared by styler and layout fragment | `PDFAnnotationKey` (`CaseIterable`), `GraphitePNG`, the format descriptors, `EditorAttributeKey` | One declaration each; golden files (`INK-INV-01` to `-08`, `EX-04`) |
| Migration names `inventory-and-links-1` to `markdown-link-written-targets-9` | `IndexSchemaMigrations` | An ordered golden list (`ARCH-INV-02`, `VAULT-INV-17`) |
| Generated file names `Pasted image yyyyMMddHHmmss`, `<note> Recording yyyy-MM-dd HH-mm.<m4a/mp4>`, `Drawing yyyy-MM-dd HH.mm.ss.<ext>` in the Gregorian calendar | `GeneratedFileNames` (Core, takes `Calendar` and `now`) | Golden names for a fixed date under a Japanese-calendar locale (`ARCH-INV-15`, `NM-01` to `NM-04`) |

### 7.4 The shape of a key declaration

```swift
/// One persisted device key: its exact name, type, default, scope and version are the whole contract.
public struct DeviceStateKey<Value: Sendable>: Sendable {
    public let name: String
    public let scope: DeviceStateScope          // .global, or .vault (name + "." + vault identifier)
    public let defaultValue: Value
    public let encoding: DeviceStateEncoding<Value>
    public let version: Int
}

/// Declared once, by the feature that owns the preference; `DeviceStateKeys.allKeys` is built from the same declarations.
extension DeviceStateKeys {
    public static let makesShapesOnHold = DeviceStateKey(name: "GraphiteMakesShapesOnHold", scope: .global,
                                                         defaultValue: true, encoding: .boolean, version: 1)
}
```

`DeviceStateStore.value(for:)` and `set(_:for:)` are the only readers and writers. `@AppStorage` is allowed only through the key's generated name and default. A golden test writes each key with the old literal and reads it through the store (`ARCH-INV-01`); a second test enumerates `allKeys` to prove vault removal deletes every `.vault` family (`FR-73`).

## 8. Navigation and routing

### 8.1 Today

A destination is wired by hand at many sites. A new document kind touches 13 UI files and three `default:` branches (`OCP-SHELL-01`, `OCP-ARCH-01`); the sidebar panel list falls back to the file tree silently (`OCP-SHELL-03`); what can be created is listed seven times (`OCP-SHELL-05`); 27 commands are declared twice, once in the palette and once in the menu bar, with shortcut labels typed in three places (`OCP-SHELL-02`, `OCP-ARCH-02`); the command palette switches the right sidebar by writing a `UserDefaults` key that the inspector reads (`DIP-ARCH-04`); the settings page list needs an entry and a switch case per configurable plugin (`OCP-SHELL-04`). The vocabularies exist as enums: `DocumentKind` with seven cases ([VaultPath.swift:155-156](../../Sources/GraphiteCore/VaultPath.swift#L155-L156)), `SidebarPanel` with four ([VaultSidebarPanels.swift:6-7](../../Sources/GraphiteUI/VaultSidebarPanels.swift#L6-L7)), `InspectorPanel` with seven ([MarkdownPane.swift:936-937](../../Sources/GraphiteUI/MarkdownPane.swift#L936-L937)), `CreationKind` with four ([VaultSidebar.swift:15-16](../../Sources/GraphiteUI/VaultSidebar.swift#L15-L16)), `SettingsPage` ([SettingsView.swift:14-19](../../Sources/GraphiteUI/SettingsView.swift#L14-L19)) and `VaultURI.Action` with six ([VaultURI.swift:10-26](../../Sources/GraphiteCore/VaultURI.swift#L10-L26)); what is missing is one descriptor per case and one place that derives every list from them.

### 8.2 One description per destination kind

Each destination kind is one enum whose cases carry pinned raw values, one descriptor value per case, registered by the module that owns the feature (section 9). Titles and symbols live in the descriptor or the string catalogue keyed by the case; nothing dispatches on a display string (`FR-17`, `FR-23`).

| Destination kind | Identifier (enum) | Descriptor | Registered by | Surfaces derived from the table |
| --- | --- | --- | --- | --- |
| Document kind | `DocumentKind`: `markdown`, `pdf`, `image`, `media`, `base`, `canvas`, `other` | `DocumentKindDescriptor`: file extensions, `holdsLinks`, `readsIndex`, session factory, pane, embedded view, creation entry, Read Aloud source | `markdown`: the shell's note-pane composition; `pdf`: PDF; `base`: Bases; `canvas`: Canvas; `image`, `media`, `other`: the shell's file preview, with the drawing re-edit hook registered by Ink | Tabs, the file tree icon and open action, quick switcher results, embeds, canvas file cards, `DocumentKind(path:)` |
| Creation | `CreationKind`: `note`, `notebook`, `base`, `canvas` | `CreationDescriptor`: title and name-prompt keys, core-plugin gate, creator returning the new path | Same module as the document kind | New menu, palette entries, empty-tab buttons, sidebar button, deep link `new` |
| Sidebar panel (left) | `SidebarPanel`: `files`, `tags`, `properties`, `bookmarks` | `SidebarPanelDescriptor`: title, symbol, core-plugin gate, view | Shell (files, bookmarks), Reading (tags, properties) | Panel picker, palette "show …" commands, `sidebarPanel` stored choice |
| Inspector panel (right) | `InspectorPanel`: `outline`, `backlinks`, `outgoingLinks`, `tags`, `footnotes`, `graph`, `map` | `InspectorPanelDescriptor`: title, symbol, core-plugin gate, view, empty-state sentence built from the registered list | Reading (five), GraphAndMap (two) | Panel picker, palette, empty-state text (today it names four of seven, `OCP-READING-05`) |
| Settings page | `SettingsPageIdentifier`: `general`, `editor`, `filesAndLinks`, `appearance`, `readAloud`, `corePlugins`, `communityPlugins`, `corePlugin(CorePlugin)`, `communityPlugin(String)` | `SettingsPageDescriptor`: title, symbol, section (`Options`, `Core Plugins`, `Community Plugins`), gate, view | The owning module: Read Aloud, Ink (drawings), Recording (audio recorder), Plugins, Shell (general) | Settings sidebar, palette "open settings" entries, deep links to a page, `OCP-SHELL-04` |
| Command | `WorkspaceCommandIdentifier` (raw values of `ARCH-INV-07`; plugin families `community-plugin:`, `community-plugin-ribbon:`, `community-plugin-view:` are an associated-value case) | `WorkspaceCommand`: identifier, title key, symbol, `KeyboardShortcut`, availability, placements, action | Every module registers its commands | Command palette, menu bar, toolbars, empty tab, context menus, hardware-keyboard shortcuts, accessibility actions; recents persisted by identifier |
| Editor command | `EditorCommand` | `EditorCommandDescriptor`: title, symbol, shortcut, surfaces | Markdown editing | Keyboard toolbar, key commands, context menu, the pane's Format menu |
| Ink selection action | `InkSelectionAction` | descriptor with title key, symbol, availability, VoiceOver label | Ink | Edit menu of the selection, accessibility actions (no dispatch on menu titles, `OCP-INK-03`) |
| Presented screen | `PresentedScreen`: the 14 sheets, covers and alerts of the root view (settings, vault manager, tab switcher, reader, creation, file management, plugins, graph, map, file recovery, image viewer, drawing editor, message alert, recording recovery) | A presentation case with its payload; the root view has one `switch` | The shell, with payloads from features | One `PresentationRouter.present(_:)`; sheet bindings are projections of it |
| Deep link | `VaultURI.Action`: `open`, `search`, `new`, `daily`, `read`, `plugin` | `DeepLinkRoute` table: action name to a `Destination` | Shell, with `plugin` forwarded to the plugin session | `DeepLinkInterpreter` (pure), queued until the last vault is restored (`ARCH-INV-13`) |

### 8.3 One routing entry point

```swift
/// Everything the workspace can show, as a value. Tabs, deep links, commands, the quick switcher,
/// the plugin API and Read Aloud links build one of these; nothing else opens a screen.
enum Destination: Hashable, Sendable {
    case document(VaultPath, anchor: DocumentAnchor?)
    case sidebarPanel(SidebarPanel)
    case inspectorPanel(InspectorPanel)
    case settings(SettingsPageIdentifier)
    case creation(CreationKind, inFolder: VaultPath?)
    case search(query: String)
    case dailyNote
    case presentation(PresentedScreen)
}

@MainActor protocol DestinationOpening { func open(_ destination: Destination) }   // WorkspaceModel is its only conformer
```

`DestinationOpening` has one production conformer and one fake, so it is a protocol only for the tests of commands and deep links (`FR-53`); it has one member. `DeepLinkInterpreter.route(for: URL, knownVaults:) -> DeepLinkRoute` is a pure function (`FR-05`): `graphite://open?vault=…&file=…` yields `.document`, `search` yields `.search`, `new` yields `.creation` with content, `daily` yields `.dailyNote`, `read` yields a `Destination` plus a Read Aloud start (and `BUG-SHELL-01` is fixed by an unresolved `file` yielding nothing), `plugin` yields a forward to the session. A command never writes a `UserDefaults` key to change a panel: it calls `open(.sidebarPanel(.tags))`, and the panel's owner persists the choice (`FR-74`).

### 8.4 Rules

1. A new destination of an existing kind is one enum case plus one descriptor; the compiler finds every exhaustive `switch` (`FR-17`, `FR-18`).
2. Identifiers are raw-value enums pinned by golden tests (`ST-06`, `ST-07`); plugin command families are typed (`FR-20`).
3. Availability is data on the descriptor (core plugin enabled, platform, an active document of a kind); each surface filters the same table (`FR-37`).
4. A shortcut is declared once as a `KeyboardShortcut`; the display glyph is derived; `.keyboardShortcut(` and `"⌘` appear only where the catalogue is rendered (`FR-23`).
5. A test builds the registry from the registration list and asserts: every `DocumentKind` case has exactly one descriptor, every command identifier is unique and stable, every shortcut appears once, every panel descriptor's gate is a real core plugin.

## 9. Feature module template

### 9.1 The registration

A feature module exposes one value. The app target's registration list is the only list of features; a feature is added by adding its line there.

```swift
// In the feature module (for example GraphiteCanvas):
public enum CanvasFeature {
    public static let registration = FeatureRegistration(name: .canvas) { registry, environment in
        registry.addDocumentKind(.canvas, descriptor: DocumentKindDescriptor(
            fileExtensions: ["canvas"],
            holdsLinks: true,
            readsIndex: false,
            titleKey: .canvasKindTitle,
            symbol: "rectangle.3.group",
            makeSession: { path, files in CanvasDocumentSession(path: path, files: files, clock: environment.clock) },
            makePane: { session in CanvasPane(session: session) },
            makeEmbeddedView: { request in CanvasEmbeddedPreview(request: request) },
            creation: CreationDescriptor(kind: .canvas, corePlugin: .canvas, titleKey: .newCanvas, namePromptKey: .canvasName)
        ))
        registry.addCommands(CanvasCommands.catalogue(environment: environment))
        registry.addSettingsPage(CanvasSettingsPage.descriptor)
        registry.addLifecycleObserver(environment.canvasDocuments)       // VaultLifecycleObserver + VaultPathMoveObserver
    }
}

// In the app target, App/FeatureRegistrations.swift: the one list.
let featureRegistrations: [FeatureRegistration] = [
    CanvasFeature.registration, BasesFeature.registration, GraphAndMapFeature.registration,
    ReadAloudFeature.registration, PluginsFeature.registration, PDFFeature.registration,
    RecordingFeature.registration, InkFeature.registration, MarkdownEditingFeature.registration, ReadingFeature.registration,
]
```

`FeatureRegistration` is a struct holding a name and a `@MainActor` closure; it is not a protocol, because nothing substitutes for it (`FR-53`). `FeatureRegistry` is a plain value with `add…` methods and read-only accessors (`documentKinds`, `commands`, `sidebarPanels`, `inspectorPanels`, `settingsPages`, `creations`, `readAloudSources`, `lifecycleObservers`, `memoryReleasers`). The shell reads only the registry, never a feature's types.

### 9.2 What each addition edits

| To add | Edit in the new or owning module | Edit elsewhere |
| --- | --- | --- |
| A document kind | A `DocumentKind` case in Core (one line); a `DocumentKindDescriptor` and its session in the module | One registration line in `App/FeatureRegistrations.swift` (none if the module already exists). Exhaustive `switch`es over `DocumentKind` fail to compile until each handles the case; there is no `default:` to hide it. |
| A sidebar or inspector panel | One enum case and one `SidebarPanelDescriptor` or `InspectorPanelDescriptor` in the owning module | The registration of that module already exists |
| A setting | A `DeviceStateKey` in the owning preferences type (section 7.4) and a `SettingsPageDescriptor` or a row in the module's page | None |
| A command | One `WorkspaceCommand` in the module's catalogue | None: palette, menu bar, toolbar, context menu and shortcuts derive from it |
| A creatable item | A `CreationDescriptor` on the document kind | None |
| A Read Aloud source (a kind of text that can be read: note, PDF page, scanned page, a future source) | A `ReadAloudSourceDescriptor`: how to build the `ReadAloudDocument` or `PDFPageLines` for a path, which `ReadAloudReading` object owns its tasks, whether it supports folds and word following | One registration line; `ReadAloudTransport` needs no change |
| A drawing format | A conformer of `DrawingFileFormat` and one entry in the format table in `GraphiteApple` | The shared `DrawingFileFormatContractTests` lists the conformer in the same commit (`FR-87`) |
| A neural model family | One `NeuralVoiceModelFamily` descriptor in Core and its renderer in `GraphiteVoices` | `NeuralVoiceManifest.json` entry |
| A Bases view type | One `BaseViewKind` descriptor (name, symbol, editor section, renderer) | None |
| A core plugin | One `CorePlugin` case and the descriptors that reference it | None |

### 9.3 The descriptor shapes

```swift
public struct DocumentKindDescriptor: Sendable {
    public let fileExtensions: [String]                         // the only place an extension is listed
    public let holdsLinks: Bool                                 // replaces "which files hold links" in three places
    public let readsIndex: Bool
    public let titleKey: StringCatalogueKey
    public let symbol: String
    public let makeSession: @MainActor @Sendable (VaultPath, DocumentFileAccess) -> any DocumentSession
    public let makePane: @MainActor @Sendable (any DocumentSession) -> AnyView
    public let makeEmbeddedView: (@MainActor @Sendable (EmbedRequest) -> AnyView)?
    public let creation: CreationDescriptor?
    public let readAloudSource: ReadAloudSourceDescriptor?
}

public struct ReadAloudSourceDescriptor: Sendable {
    public let supportsFolds: Bool
    public let followsWords: Bool
    public let makeReading: @MainActor @Sendable (ReadAloudReadingContext) -> any ReadAloudReading
}
```

`ReadAloudReading` is a protocol because `MarkdownReading`, `PDFReading` and `ScannedPageReview` are three production conformers (`SRP-VOICE-01`, `FR-14`). `DocumentSession` has the six members of section 5 and one contract suite.

### 9.4 A feature that is off does not run (owner, 2026-10-20)

Graphite is a small kernel plus features, and a feature that is switched off, or left out of the registration list, costs nothing: no memory, no launch time and no work (decision 15, `FR-109`). Read Aloud already works this way ([Architecture.md](../Architecture.md), "Read Aloud as a core plugin"): while it is off no voice library, renderer, synthesizer or Now Playing entry exists, turning it on builds them without a relaunch, and turning it off stops and releases them. The community plugin runtime starts no web view while no plugin is enabled ([CommunityPluginHost.swift:393](../../Sources/GraphiteUI/CommunityPluginHost.swift#L393)). The other core plugins are switched where they are used: 19 places in `GraphiteUI` test `preferences.isEnabled(…)` (for example [WorkspaceModel.swift:417](../../Sources/GraphiteUI/WorkspaceModel.swift#L417), [WorkspaceModel.swift:862](../../Sources/GraphiteUI/WorkspaceModel.swift#L862), [WorkspaceRecovery.swift:19](../../Sources/GraphiteUI/WorkspaceRecovery.swift#L19)), and what each builds while it is off has not been inventoried (Phase 6, step 9).

1. **The kernel** is what cannot be switched off: vault access and storage, the index, the file list, the Markdown note editor and reading view, tabs and windows, and Settings. Everything else is a feature with a `CorePlugin` switch, including the ones that have none today: search, PDF, notebooks and Pencil drawing, recording, notebook import, community plugins and community themes (decision 16).
2. **Off means not built.** The composition root builds a feature's services, models, caches, observers, tasks, timers, file monitors and web views only while its switch is on. Its descriptors (document kinds, panels, commands, creations, settings pages, Read Aloud sources) are not registered while it is off, so no menu, panel or view tests the switch; only its row in Settings › Core Plugins remains. A file whose kind belongs to a feature that is off opens as an ordinary file preview, as in Obsidian.
3. **Work that serves one feature stops with it.** Index queries, vault-change observers, configuration reads at launch and preparation work that only one feature uses (Bases record queries, map coordinates, graph layout, tag and property counts, file-recovery copies) run only while a feature that needs them is on.
4. **On and off at run time.** Turning a feature on builds it without a relaunch. Turning it off saves what it holds, stops its work and releases every object, and deletes nothing in the vault or on the device; deleting downloaded data is a separate, confirmed action, as it is for Read Aloud's voices.
5. **Left out at build time.** A feature that is not in `App/FeatureRegistrations.swift` is not linked into the app. A composition with the kernel only builds and launches, so a lighter build, or a build without a feature that is broken, is one line.
6. **Checked, not promised.** For each feature, `FeatureSwitchTests` turns it off and asserts, from the registry's record of what each registration built, that none of its objects exists (weak references are nil after the switch) and that none of its tasks or observers runs. The `FR-101` budgets include cold launch and idle memory with every feature off, with the default set, and the increment each feature adds; a change that grows a feature's increment beyond its budget does not land.

## 10. Concurrency, errors and the design system

### 10.1 Concurrency model

1. **UI and models are main-actor.** Views, `@Observable` models and anything UIKit or AppKit touches are `@MainActor`. Services that do I/O, parsing, diffing, encoding or hashing are actors or `nonisolated` functions that run off the main actor; payload decoding for plugin messages happens off the main actor and the model receives a typed value (`FR-69`, `CC-PLUGIN-06`, `CC-VOICE-13`).
2. **Actors own mutable state.** `VaultFiles`, `VaultScanner`, `VaultIndex`, `PDFFileService` and `ReadAloudAudioCache` are actors that own their state; nothing outside reads it without `await`. A live framework object does not cross actors unless its documented thread-safety says so (`RULES.md`).
3. **A task has an owner.** Every `Task`, timer, observer and subscription is stored by an owner whose teardown ends it: the model that started it, or `OpenVault` for vault-scoped work (`vaultWillClose()` cancels). A view closure calls one synchronous model method and never contains `Task { }` (`FR-66`).
4. **Cancellation is structured and visible.** A cancelled operation throws `CancellationError` and is never converted into a value; `try? await Task.sleep` is forbidden because it keeps running after cancellation (`FR-66`).
5. **Await completion; never sleep to order work.** The 51 `Task.sleep` and 10 `asyncAfter` sites that order work become awaits of the running task, `AsyncStream` events, a continuation resumed by the owner, `onDismiss`, or a task's `value`. The two documented exceptions are a bounded wait on the camera queue (`CC-LECTURE-12`) and UIKit's "after the current update" hop, routed through `EditorRunLoopScheduler` (`FR-65`).
6. **Three shared primitives, one file.** `Debouncer` (on `ApplicationClock`), `LatestRequest` ("latest answer wins": starting a request cancels the previous, results apply by identifier against the current value, never against a value read before the await; its specification is the run-identifier behaviour of `WorkspaceModel`, `ARCH` keep) and `withTimeout` ("first outcome wins", cancels the loser). They live in `GraphiteCore/Concurrency/ConcurrencyPrimitives.swift`, each with one test; `withTaskGroup` and generation counters appear nowhere else (`FR-67`).
7. **Events are streams.** Adapters publish `AsyncStream`s (speech events, runtime channel `incoming`, conflict listings) instead of settable closure slots such as `eventHandler` ([ReadAloudSpeech.swift:102](../../Sources/GraphiteApple/ReadAloudSpeech.swift#L102)); a consumer cancels its subscription on teardown (`FR-42`, `FR-43`).
8. **Where unsafe escapes may live.** `@unchecked Sendable`, `nonisolated(unsafe)` and `MainActor.assumeIsolated` appear only in one file per module named `<Module>/Concurrency/UncheckedConcurrency.swift` (allow-listed), each declaration carrying the invariant on the same or the preceding line. Today there are 20 `@unchecked Sendable`, 4 `nonisolated(unsafe)` and 41 `assumeIsolated` (`CC-ARCH-06`, `CC-LECTURE-15`); the migration moves them into those files and replaces `assumeIsolated` with `Task { @MainActor in … }` except inside a callback the API documents as delivered on the main queue (`FR-70`).
9. **JavaScript is single-threaded and uses an injected scheduler.** The runtime's `coalesced-notifier.js` takes a scheduler so that tests replace the 20 ms `settle()` and the 5 ms poll (`CC-RUNTIME-03`, testing 4.7).
10. **Time is injected.** Logic takes `ApplicationClock`; only `LiveApplicationClock` reads `Date()`, `ContinuousClock.now` or `systemUptime` (`FR-50`).

### 10.2 Errors and the one presenter

1. **Typed, per area, in the lowest module that detects the failure.** `VaultError`, `CanvasFileError`, `BaseError`, `RecordingError`, `PDFSaveError`, `CommunityPluginFailureKind`, `ReadAloudError` and the port error enums of section 5.2 carry facts (`alreadyExists(VaultPath)`, `tooLarge(limitBytes:)`, `missingSection(subpath:note:)`, `skippedHeadersAndFooters`). They conform to `Error` and `Equatable`; no protocol joins them. The 84 prose `GraphiteError` constructions in Core are replaced; no case carries a sentence (`FR-55`, `FR-63`).
2. **One `WorkspaceAlert` enum** in `GraphiteShell` has one case per error family with the typed error as payload, plus notices (`.notice(Notice)`). Features return typed results or throw typed errors to their model, which hands them to `WorkspaceAlerts`; no feature holds a `String?` outcome and the 80 operations that share `errorMessage` stop sharing it (`SRP-SHELL-03`, `FR-12`).
3. **One `ErrorPresenter`** maps a `WorkspaceAlert` to `AlertPresentation` (title, message, actions, and whether it is an alert, a banner or silent) with an exhaustive `switch`; wording comes from the string catalogue keyed by the case. It adopts the rule of `MessageAlert`: the alert is titled by its first sentence ([MessageAlert.swift:6-34](../../Sources/GraphiteUI/MessageAlert.swift#L6-L34), kept). Nothing shows `error.localizedDescription` to a person; debug detail goes to `Logger` (subsystem `com.graphite.study`) only (`FR-64`).
4. **The queue never overwrites.** `WorkspaceAlerts` is an ordered queue; a second failure appears after the first.
5. **`try?` needs a reason.** The same line carries a comment saying why failure and absence mean the same; the scan `grep 'try?' | grep -v '//'` is a ratchet that ends at zero (Phase 14). A swallowed save, delete, safety copy or read whose emptiness the person would see is a defect (`FR-58`, `FR-60`).
6. **Unreadable data is moved aside, never overwritten.** A list decodes element by element, an element that does not decode is kept as `unknown(raw)` and written back, and a file that does not decode as a whole moves aside under a versioned name (`FR-61`).

### 10.3 Design tokens and the string catalogue

No audit finding asks for design tokens; this part comes from the house rule set and is scheduled last (Phase 13), after the structure it depends on. The audit does find that views have no string catalogue and that the model writes user-facing text (`CC-SHELL-06`), and that Core, Apple and Voices produce user-visible English (`CC-VOICE-10`, `CC-BASES-07`, `CC-CANVAS-03`, `DIP-MDCORE-02`).

1. **Tokens.** `GraphiteDesign` declares spacing, corner radii, typography roles and semantic colours (text, surface, separator, accent, state) with light, dark and increased-contrast variants. Views use tokens only; a raw literal colour, size or font in a view is a review finding. Colour tokens have contrast tests (text on surface at or above 4.5 to 1, large text and controls at or above 3 to 1) in the unit suite. The vault theme's colours reach notes through `NoteThemeStyle`, not through tokens.
2. **String catalogue.** Each module that shows words owns a `Localizable.xcstrings` resource with keys named after the case (`vault.error.alreadyExists`), plural variants through catalogue plural rules, and shared words in `GraphiteDesign`. User text is a `LocalizedStringResource`, built only in presenters and views; a literal sentence in a `Text("…")` outside the catalogue is a finding (`FR-55`). A catalogue test asserts every presenter case has an entry (`FR-91`). Whether other languages ship is owner question 10; the structure is the same.
3. **Facts, not words, below the UI.** Core, Index, Apple and Voices return typed values; a `displayName` or an `errorDescription` that returns a sentence in those modules is removed (`FR-55`).

## 11. The rules new code is held to

The 121 numbered rules of the six principle documents (`SRP 1` to `20`, `OCP 1` to `14`, `LSP 1` to `17`, `ISP 1` to `18`, `DIP 1` to `17`, `CC 1` to `35`) and the 23 testing rules (`TR 1` to `23`), 144 in all, are merged into 100 rules, `FR-01` to `FR-100`; group I (`FR-101` to `FR-108`) adds the owner's performance and reliability goal of 2026-10-18, and group J (`FR-109`, `FR-110`) the owner's direction of 2026-10-20 on features and packages. Rules that state one requirement from two or three principles are one rule (for example, `SRP 2`, `ISP 1` and `ISP 2` all say that no consumer takes the application root). Every source rule lands in at least one `FR` rule, and no source rule is dropped; the coverage table after the rules lists where each one landed, and a script (`scripts/check-rules.py --coverage`, Phase 1) verifies that every `SRP n`, `OCP n`, `LSP n`, `ISP n`, `DIP n`, `CC n` and `TR n` of the principle documents appears in a Sources cell. Each rule is one or two sentences with "must", and its checks (greps and counts) are in the principle document it comes from; Phase 1 turns those checks into a ratchet (section 12). `RULES.md`'s warning applies to every rule: a protocol only where a second implementation or a stated test or isolation need exists, and no layer that only forwards.

### A Responsibility

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-01** | **One aggregate and one kind of work per type.** A type that holds state must own one aggregate (an open vault, one note's text, one canvas file, one PDF, one reading, one plugin session) and one kind of work (deciding, storing, presenting or adapting a platform API). A class with more than 15 stored properties must record in its doc comment the responsibilities that justify it. | `SRP 1` |
| **FR-02** | **No consumer takes the application root.** Only the composition root and the scene that owns `WorkspaceModel` may store it; a view, model, service or function must take the narrow model or capability it uses (never `WorkspaceModel`, `CommunityPluginHost` or `PDFSession` whole). Leaf views must take values and intent closures, container views at most one feature model, and the composition root holds no state and no rules. | `SRP 2`, `ISP 1`, `ISP 2` |
| **FR-03** | **A feature owns its state and extends nothing foreign.** New behaviour of a feature must live in a type the feature owns; an `extension` of an aggregate must sit in that aggregate's own group of files, and no extension may write another feature's state. A feature must add no stored property and no reset line to the application aggregate. | `SRP 3`, `OCP 9` |
| **FR-04** | **A lifetime ends by replacing or releasing one value; cross-cutting duties are opt-in.** State that lives for one vault, runtime, reading or session must be held in one value that the owner replaces; a function that assigns five or more fields back to empty values is rejected. Move, delete, vault switch, vault removal and memory release must iterate registered `VaultPathMoveObserver`, `VaultLifecycleObserver` and `MemoryReleasing` conformers and name no feature. | `SRP 4`, `OCP 8` |
| **FR-05** | **Decide, then do.** A function that decides (what to insert, which range, which repair, which retry) must be pure: inputs and `now` in, a value or plan out, in Core when it compiles on both platforms. A separate type performs the plan, and an orchestrating function names its stages and holds none of their details. | `SRP 5` |
| **FR-06** | **Platform delegates are adapters, and the iPad and Mac editors share their decisions.** A class that conforms to platform delegate protocols must forward each callback to an owned collaborator and keep only the state needed to forward; a `PKCanvasView` subclass records history and nothing else. A decision that both coordinators make must live in one shared type, and a `#if os` block must contain platform calls only. | `SRP 6`, `CC 14` |
| **FR-07** | **UI code does no I/O and decides no rule.** A view, view task, `body` or drawing closure must not touch `FileManager`, `AtomicFileWriter`, `URLSession`, an installer, `UserDefaults`, the pasteboard or `Task.sleep` for a rule, and must not parse notes. Each UI event must call one model method that returns a typed result. | `SRP 7` |
| **FR-08** | **Reads do not write.** `body`, `draw`, `Canvas` closures, getters, predicates, view initialisers, `layoutSubviews` and `updateUIView` must not write observed state, write a file, start a task, move a view or build a service; they may write an `@ObservationIgnored` memo. Geometry that drawing and hit testing both need must be one pure function, and a refresh is a named intent called from `.task`, `.onChange` or the owning model. | `SRP 8`, `CC 18` |
| **FR-09** | **Work that must happen has an owner that exists without a view.** Autosave, release, background inspection and every other duty must be started and cancelled by a model or session; a hidden view (`Color.clear`, a zero-size driver) must not own it. | `SRP 9` |
| **FR-10** | **Every business rule has exactly one owner.** A rule (link resolution, fence and block detection, applying an edit to a note open or closed, fitting, image-reference classification, frontmatter location, file URL to vault path) must be implemented once, in the type that names it, with tests. A second implementation is allowed only as a documented performance mirror with a parity test over a shared corpus. | `SRP 10`, `LSP 1`, `CC 13` |
| **FR-11** | **A flow with more than two states is one enum.** Booleans and optionals that must be set together, a lifecycle of three or more phases and a set of mutually exclusive modes must be one enum or struct changed only through intent methods; stored Boolean groups, `didSet` resets and sentinel offsets must not encode phases. | `SRP 11`, `OCP 11`, `CC 8` |
| **FR-12** | **Outcomes and requests travel as values.** An operation must return or throw a typed outcome; a request to another object must be a method call or an entry in a typed queue the receiver drains, never a field the receiver polls. A "performing own edit" flag must be set by a scoped helper with `defer`, derived state must advance only after the operation succeeds, and the result of an `await` must be applied by identifier against the current value. | `SRP 12`, `ISP 9`, `CC 12` |
| **FR-13** | **Derived state is a projection of its inputs.** A value that is a function of another must be computed or projected from one place; no correctness may depend on a caller remembering a follow-up call, and no view keeps its own copy of controller state. | `SRP 13` |
| **FR-14** | **A controller serving several kinds of work holds one active value of the current kind.** A controller for audio and video recording, or Markdown and PDF reading, must hold one optional active session of the current kind, behind a protocol only where two production implementations exist; fields of one kind must not be live in the other. | `SRP 14` |
| **FR-15** | **A settings store serves one feature area and one scope.** A preferences type must own the keys of one feature area over the typed registry; per-vault state must not live in a per-device store, and a settings baseline must travel in the value the read returns. | `SRP 15` |
| **FR-16** | **Runtime script objects own one responsibility and their own fields.** In the plugin runtime each file must export one object with one responsibility, receive its collaborators at construction and declare every field in its constructor; other files change a field only through a method of that class, and no code reads or writes the global `GraphitePluginRuntime` as a registry. | `SRP 19`, `ISP 18` |

### B Extension

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-17** | **One case, one descriptor, one table.** Adding a document kind, sidebar or inspector panel, creatable item, settings page, Bases view type, block kind, drawing format, model family or core plugin must be one enum case plus one descriptor registered by the module that owns the feature; menus, pickers and empty-state text must be derived from that table. | `OCP 1` |
| **FR-18** | **No `default:` over an own enum.** A `switch` over an enum declared under `Sources/` must name every case: no `default:`, no catch-all `case .x:` for an enum with associated values, no `case .x where condition` followed by `default:`, and no `if/else` chain over an enum that ends in a fallback branch. | `OCP 2` |
| **FR-19** | **Per-kind behaviour is data on the descriptor.** A decision that differs by kind must be a property of the kind's descriptor read through one exhaustive switch; it must never be an equality test such as `== .pocketTTS` or `language.name == "shell"`. | `OCP 3` |
| **FR-20** | **External strings are mapped once, at the boundary, to an enum with `unknown(raw)`.** A value read from a file format, manifest or settings file must be decoded once in Core into an own enum with an explicit `unknown(String)` case; the raw field stays the stored truth so unknown values round-trip, and no code outside the mapping compares the raw string. | `OCP 4` |
| **FR-21** | **A vocabulary shared with JavaScript, CSS or a script is generated from one declaration.** Message operation names and payload fields, theme-probe keys, callout types, code token classes, `BaseValue` wire types and diagnostic record kinds must be declared once, as a `String` raw-value enum or one JSON schema; the JavaScript constants, CSS lists and the Node fake host's switch must be generated from it and CI must regenerate and diff. | `OCP 5` |
| **FR-22** | **An unknown operation is a failure, never a success.** Every receiver of a message protocol (the Swift host, the vault bridge, the runtime, the fake host) must answer an operation it does not know with the typed `unknownOperation` failure, and routing must be by the decoded enum, not by a name prefix. | `OCP 6` |
| **FR-23** | **Each command surface declares its commands once and renders them everywhere.** The workspace, the editor and the ink selection must each declare a command once (identifier, title, symbol, `KeyboardShortcut`, availability, placement, action); the palette, menu bar, toolbars, context menus, key commands and accessibility actions must be built from that declaration, and persisted identifiers are the cases' raw values. | `OCP 7` |
| **FR-24** | **One fact, one declaration; a name that is read and written has one registry.** A table that restates another (sort ranks, annotation keys, media extensions, templates) must be derived through `CaseIterable`, a computed property or a shared function. A key, alias or option name accepted under several spellings must come from one typed registry that the reader and the editor use, and a setter must write the canonical key and remove aliases. | `OCP 10`, `LSP 14` |
| **FR-25** | **Extension is by registration, never by mutating another file's objects.** A runtime feature file must add its handlers through one registration call that is valid whenever it runs before `runtime.start`; it must not copy into, assign into or patch another file's objects or prototypes, and the script order in `index.html` must change no handler table. | `OCP 12` |

### C Contracts and substitution

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-26** | **One name, one platform contract.** A type with a UIKit body and an AppKit body under one name must serve the same inputs, gestures and duties on both, and must not declare an input one body ignores; a body that cannot serve an input must be a differently named type, or the input must exist only where it is served. | `LSP 2` |
| **FR-27** | **Equality compares every behavioural input.** A type's `==` and `hash(into:)` must cover every stored input that changes what it renders or does; a deliberate partial `==` is allowed only when its doc comment states the invariant and a test pins it. | `LSP 3` |
| **FR-28** | **Identity comes from stable structured content.** An `Identifiable.id`, fold key, persisted key or recognition test must derive from the source line, a stored identifier plus occurrence count, an object identity or a session UUID, never from a label, a rewritten display string, a `hashValue` or an element index; words must not be derived from a persisted raw value, and a command is found by its identifier. | `LSP 4`, `OCP 13`, `CC 21` |
| **FR-29** | **A success answer is computed from what happened.** A method that reports success, a count or a stand-in answer must derive it from the returned outcomes of the work, not from the number of attempts, from "a file exists at the destination" or from a constant; a stand-in that cannot do the work throws or reports "unsupported" by name. | `LSP 6` |
| **FR-30** | **A protocol states its contract and every conformer meets all of it.** Each protocol with more than one conformer must document ranges, events, failures and which request fields it honours; a capability an adapter lacks must be a value it reports (`supportedSpeedRange`, word timing per request), never a silent default or a clamped value. | `LSP 7` |
| **FR-31** | **No forwarding defaults and no no-op conformances.** A protocol extension must not provide a default that forwards to another requirement with fewer fields, and a conformer must not implement a mutating requirement as an empty body or a sentinel; a conformer that would stub a requirement means the protocol is too wide and must be split. | `LSP 8` |
| **FR-32** | **No test-only mode, entry point or state in production types.** A production type must not carry a property, branch or method that only a test sets or calls; tests reach states through the production path with an injected port, and a test that pins a function production never calls moves to the function production calls. | `LSP 13`, `TR 4` |
| **FR-33** | **A function name states its scope.** Functions that stop, cancel, clear or reset must take or carry a scope enum, or have a name that states it; two functions with the same verb in one feature must differ by scope in the signature, and every control for one user action must call the same function. | `LSP 15` |
| **FR-34** | **Recognise one thing once, from one input.** When two inputs can trigger the same recognition (preview and commit, hold and lift), the result must be computed once, in one coordinate space, and the commit must use the previewed result; tests must feed the two paths different inputs, including a zoom other than 1. | `LSP 16` |
| **FR-35** | **Refusals are reported and every owner of a step honours the same refusal.** When an undo, history or patch step is refused, the owner must report it and keep the history consistent; two owners of one change type must use one helper with one refusal behaviour. | `LSP 17` |

### D Interfaces

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-36** | **No back-reference from a service to its owner.** A long-lived service (the plugin host, a health monitor, a completion provider) must not hold a `weak var` to the workspace or a coordinator; it must receive a capability value owned by the service's module. | `ISP 3` |
| **FR-37** | **At most seven members per capability; availability is data.** A protocol, struct of closures or environment value must have at most 7 members, and when two consumers use disjoint subsets it must be split along them. Whether a feature is offered must be a value (`Set<EditorFeature>`, an optional narrow capability), not an optional closure that means both "available" and "action". | `ISP 4`, `ISP 12` |
| **FR-38** | **Reading and destroying are separate capabilities.** A consumer that only lists, reads or discovers must receive an interface without `delete`, `move`, `remove*`, `replace*` or `save*` members; destructive members live in a separate interface given only to the workflow that performs the destruction. | `ISP 5` |
| **FR-39** | **Sessions depend on `DocumentFileAccess`, not on `VaultStore` or `VaultIndex`.** Document sessions and builders must take the document-file capability (`read`, `save(expecting:)`, `fileExists`, `uniquePath`) and, where needed, a feature-owned index capability; they must never store the vault actors. | `ISP 6` |
| **FR-40** | **Model state with an invariant is `private(set)`; views call intents.** In an `@Observable` model, every stored property that an invariant, a one-way decision or an ordering rule depends on must be `private(set)`; views change it only through named intent methods, and a `Binding(get:set:)` may call an intent but must not assign a model field. | `ISP 7` |
| **FR-41** | **Views talk to the controller, never to the controller's parts.** A view must receive the transport or status projection it shows and must not reach through a controller into its session (`reader.session.play()`). | `ISP 8` |
| **FR-42** | **Window-wide services take registrations keyed by identity.** A service shared by several panes must accept per-note or per-pane registrations that are removed on disappear, and must not expose one settable closure slot that the last writer owns. | `ISP 10` |
| **FR-43** | **A platform view talks to its owner through one weak reference.** A `UIView` or `NSView` subclass must not expose settable closure properties for its owner to fill in after construction; it must hold one `weak var owner` with methods, and configuration values go into the initialiser. | `ISP 11` |
| **FR-44** | **No untyped dictionary crosses a boundary; a file is read and written through one type.** Structured data crossing modules, WebKit, diagnostics or a vault file must be a `Codable` type decoded once at the edge, a missing field is a typed decoding error and never a default, and `Any` must not be returned from a parser. Every user-visible file Graphite rewrites must have one type for decode and encode, so the writer is never narrower than the reader. | `ISP 13`, `ISP 14` |
| **FR-45** | **A value's fields apply to all its cases; shared parameters travel as one context value.** A struct field meaningful for one kind of value must move into the payload of an enum case, and no field may be documented as "only for X". When three or more helpers take the same four or more parameters they must take one context value, keeping signatures at 6 parameters or fewer. | `ISP 15`, `ISP 17` |

### E Dependencies

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-46** | **The app target is the only composition root.** Every adapter that touches disk, `UserDefaults`, the network, WebKit, AVFoundation, shared PencilKit state, the keychain or the clock must be constructed in `GraphiteApp.init` through `AppEnvironment`, or in a factory the environment owns; models, sessions and views must receive it through an initialiser or a SwiftUI `@Environment` entry. | `DIP 1` |
| **FR-47** | **No default argument chooses a dependency or a semantic fallback.** A parameter of type `UserDefaults`, `URLSession`, `AtomicFileWriter`, `FileManager`, a speech, capture, storage or provider protocol, or a clock must have no default value, and an optional dependency must never be replaced by a different implementation inside the callee. | `DIP 2`, `LSP 9` |
| **FR-48** | **No singleton, service locator or mutable static.** `static let shared`, static stored service references, `static var`, `static weak var` and a `static let` holding a mutable container must not be added; process-wide services live in `AppEnvironment`. Exceptions are immutable constants, stateless delegates and bounded memoisation of system-derived values, each declared in one allow-listed file with its reason. | `DIP 3` |
| **FR-49** | **A collaborator that is passed in is the only one used.** A type that receives an instance must read, observe and post notifications on that instance, never on a global of the same type; every `addObserver(forName:object:)` names a stored or injected object. | `DIP 4` |
| **FR-50** | **Time, calendar and randomness come from one injected source.** Logic must take `now`, a `Calendar` and a `RandomNumberGenerator` as parameters or from `ApplicationClock`, with no default value; only the live clock adapter reads `Date()`, `.now`, `ContinuousClock.now`, `systemUptime`, `TimeZone.current`, `Calendar.current`, `randomElement()` without a generator, `Math.random()` or `Date.now()`. | `DIP 8` |
| **FR-51** | **File and network I/O live only in adapters.** Views, view models and Core policy must not call `FileManager`, `Data(contentsOf:)`, `FileHandle`, `URLSession` or `JSONSerialization` on files; a vault file must be read through the vault capability (coordinated, path-validated), a policy that decides from content must take the bytes as a parameter, and remote images and plugin downloads go through an injected ephemeral session. | `DIP 9` |
| **FR-52** | **Platform singletons stay at the edge.** `UIApplication.shared`, `NSWorkspace.shared`, `UIDevice.current`, `UIScreen.main`, `NSScreen.main` and `UIPasteboard.general` must be read only in platform adapters or the top-level view that turns them into values; models, coordinators and drawing code receive a capability. | `DIP 10` |
| **FR-53** | **A port is a protocol only when substitution is real.** A protocol must have two production implementations or a stated test need it cannot otherwise meet, state the reason on its declaration, have at most about 7 members, be declared by the consuming module and have one contract suite; a single capability is a closure or a struct of closures. A descriptor protocol earns its place the same way, and kinds without a real substitution stay value-type descriptors behind one exhaustive switch. | `DIP 11`, `OCP 14` |
| **FR-54** | **A module holds one layer, and dependencies point inward.** `GraphiteCore` must contain values, parsers, policies and planners only (no `FileManager`, `URLSession`, keychain or Application Support); adapters live in modules the consuming layer's ports describe, new feature code goes in a feature module, and a plain value type lives in Core, not in an adapter. A feature must not name `WorkspaceModel` or another feature's type for a shared rule. | `SRP 18`, `DIP 13` |
| **FR-55** | **Domain code returns facts; one presenter and a string catalogue word them.** Core, Index, Apple and Voices code must return typed facts and identities and must not build user-visible sentences, colour names or labels; UI text comes from a string catalogue with plurals, and notices, issues and problems are typed values with associated data. | `DIP 14`, `CC 15` |
| **FR-56** | **Launch modes are compositions; measuring tools and test hooks do not ship.** A launch mode (app, voice benchmark, hosted tests) must be parsed once in the composition root and select a different `AppEnvironment`, never a flag read inside a production view; benchmark screens and test accessors live in the benchmark or test-support target. | `DIP 15` |
| **FR-57** | **Runtime classes receive a narrow host channel; page-wide patches are scoped and named.** JavaScript classes that talk to Graphite must receive a `HostChannel` through their constructor and must not read `runtime.hostBridge` or `runtime.app`; a class must not call up into a layer that observes it, and a patch of a platform prototype must live in one file named for it, apply only to the elements that need it and record why event delegation does not work. | `DIP 16` |

### F Errors, concurrency and state

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-58** | **`try?` states why.** `try?` must appear only where failure and absence mean the same to the caller, and the same line must carry a `//` comment saying why; a `try?` on a write, a safety copy, a delete or a read whose empty result the person would see is a defect, and an empty `catch {}` follows the same rule. | `CC 1` |
| **FR-59** | **A failed read is never an empty result.** A function that reads stored or external data must return or throw a typed state that separates `missing`, `contents` and `unreadable(Error)` and must never turn a failure into `[]`, `0`, `""`, `nil` or defaults; callers treat only `missing` as "use defaults". | `LSP 5`, `CC 2` |
| **FR-60** | **A destructive step stops when its safety copy fails, and writes report failure.** A delete, overwrite, restore, replace or quit-time save must run its safety copy and its write inside `do/catch`, stop when the safety copy fails, and report a failed write to the caller and the person; application termination must wait for the save and report its outcome. | `CC 3` |
| **FR-61** | **Unreadable stored data is kept, never overwritten.** Lists of stored data must decode element by element and keep an element that does not decode as `unknown(raw)`; a file that does not decode as a whole must be moved aside under a versioned name, and code must never write defaults over data it failed to read. | `CC 4` |
| **FR-62** | **Constant patterns compile through one helper.** A constant regular expression must be compiled once through one `StaticPattern` helper that fails fast on a malformed literal, with one unit test that touches every pattern; `try?` stays only for patterns a person supplies. | `CC 5` |
| **FR-63** | **Errors are typed values that carry facts.** Core, Index, Apple and Voices code must throw and return typed values with facts (`.alreadyExists(VaultPath)`, `.tooLarge(limitBytes:)`); callers must branch on the case, never on message text, and one catch-all case must not stand for several failures. | `CC 6` |
| **FR-64** | **One presenter turns failures into words.** One presenter must map typed failures to catalogue strings and decide alert or banner; code must not show `error.localizedDescription` to the person, a feature must not hold a bare `String?` outcome so that a second failure never overwrites the first, and detail goes to the `Logger` only. | `CC 7` |
| **FR-65** | **Await completion; never sleep to order work.** Code must not sleep, poll or hop to the next run-loop turn to wait for other work; it must await the completion signal. The only exceptions are a bounded wait on a dedicated media queue with named limits and UIKit's documented "after the current update" hop routed through one owned scheduler. | `CC 9` |
| **FR-66** | **Every task, timer and observer has an owner that ends it.** Each `Task`, timer, observer and subscription must be stored by an owner whose teardown cancels or removes it; a `View` closure calls one synchronous model method and the model starts and stores the task, and `try? await Task.sleep` is forbidden. | `CC 10` |
| **FR-67** | **One tested primitive per timing pattern.** Debounce, "latest answer wins" and "first outcome wins" must each use one shared, tested primitive (`Debouncer`, `LatestRequest`, `withTimeout`) on the injected clock, in the allow-listed primitives file; a feature must not write a generation counter or a timeout race by hand. | `CC 11` |
| **FR-68** | **A guard every caller must remember lives at one boundary.** A bound or check that all call sites must apply must be applied inside one function that nobody can bypass: `BoundedMarkdownParser` is the only place `Document(parsing:)` appears, every recursive rewriter takes a depth parameter with a named maximum, and a filter of untrusted markup is an allow list. | `CC 16` |
| **FR-69** | **Hot paths cost the change, not the collection.** Work on the typing, drawing and scrolling paths must be proportional to the change and off the main actor when it is not UI work: layout passes place geometry only, menus are built when the selection changes, parsing, diffing, encoding and serialisation run in a detached task, and overlap tests use a sorted range set. | `CC 19` |
| **FR-70** | **Every concurrency escape names its invariant and lives in the allow-listed file.** `@unchecked Sendable`, `nonisolated(unsafe)` and `MainActor.assumeIsolated` must carry a comment on the same or preceding line naming the invariant, and may appear only in the module's allow-listed concurrency file; `assumeIsolated` is allowed only inside a callback the API documents as delivered on the main queue. | `CC 28` |
| **FR-71** | **No trapping on file data.** Parsing and file-handling code must not use `try!` or a force unwrap, and a keyed lookup repeated after a sort is replaced by carrying the pair through the sort. | `CC 29` |
| **FR-72** | **Every cache has an owner, a bound and a truthful policy.** A cache, retained collection or per-document map must be an instance created by the composition root or a feature model, bounded by a named limit with an eviction policy that the code implements and the comment describes, and its owner must conform to the memory-release and vault-close duties; files written per input are pruned at write. | `DIP 12`, `CC 30` |
| **FR-73** | **Every persisted key has one typed declaration and one store.** Every persisted key, file name and notification name must be declared once in a typed registry with its exact name, value type, default, encoding, scope and version, and read and written only through the `DeviceStateStore` over an injected `UserDefaults`; `@AppStorage` may use only the registry's key and default, and per-vault keys must be enumerable so a vault's removal deletes all of them. | `DIP 5`, `CC 20` |
| **FR-74** | **Persisted state is not a message channel.** A command or model must change what a view shows by calling an intent method on the view's model; only the owner of a persisted choice writes its key, and no code observes `UserDefaults.didChangeNotification`. | `DIP 6` |
| **FR-75** | **Code that runs per touch, stroke, frame or layout takes preferences as values.** Such code must receive preferences as a value its owner observes once, and must not read `UserDefaults` or any store itself; pure deciders take the value as a parameter. | `DIP 7` |

### G Size and style

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-76** | **Functions do one thing at one level.** A function must do one meaningful thing at one level of abstraction. A function over 40 code lines needs a recorded design review, nesting is at most 5, parameters at most 6, lines at most 160 characters, and a SwiftUI `body` over 60 code lines is split into named subviews; an exhaustive single-switch mapper and a long straightforward sequence may stay whole. | `SRP 16`, `CC 17` |
| **FR-77** | **One concept per file, named after it.** A file must hold one concept and be named after it; it is split by responsibility, never by size and never as `Part1` or `Part2`, when it needs a name like `Manager`, `Helper` or `Utils`, holds unrelated types, changes for different reasons or has a section that could be tested alone. A primitive other features use lives in a file named after it. | `SRP 17`, `CC 27` |
| **FR-78** | **No literal duration, threshold, cap or size in logic.** A duration, cap, ratio or size must be a named constant with its unit in the name (`…Milliseconds`, `…Bytes`, `…Points`) on the type that owns the policy, declared once; days, months and years use `Calendar`, never `N * 86_400`. | `CC 22` |
| **FR-79** | **Embedded code lives in resource files.** JavaScript, HTML, CSS and template documents of more than a few lines must live in resource files that are linted and have behaviour tests; a Swift string holds a one-line expression at most (SQL beside its GRDB call excepted). | `CC 23` |
| **FR-80** | **Comments state the current rule.** A comment must state the rule the code keeps, in the present tense, with no date, device, owner, "used to" or incident story; the incident goes in the commit message and in the name of the regression test. A doc comment sits directly on its declaration, and a comment that contradicts the code is a defect. | `CC 24` |
| **FR-81** | **Names are full words that state the role.** A name must use complete descriptive words, state the type's real role and its units, and a Boolean must read as an assertion; one concept has one name in code, UI and docs, and generic or abbreviated names are allowed only where a platform or file-format API names them. | `CC 25` |
| **FR-82** | **Nothing unused ships.** A declaration without a production caller must be deleted and a member that only tests call lives in the test-support target; a dead-code scan runs in CI. | `CC 26` |

### H Testing

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-83** | **Tests are discovered and named after the production type they pin.** Every test file must run without editing a project file (the hosted target uses a synchronised folder); tests are in one class per file named after the production type (`BaseEvaluatorTests.swift`), with method names that state a behaviour in a sentence, and names with `Fix`, `Regression`, `Handoff`, a round or a date are forbidden. | `TR 1`, `TR 2`, `CC 32` |
| **FR-84** | **A test lives in the target of the module that owns the type.** A test file's imports must match its folder; no `GraphiteCore` type is tested from `GraphiteIndexTests`. | `TR 3` |
| **FR-85** | **Shared test support, one `waitUntil`.** `GraphiteTestSupport` must provide temporary vaults, isolated `UserDefaults(suiteName:)`, an injected clock and one event-based wait; temporary files come from `TemporaryVault`, and a helper copied into a third file moves to the support target in the same commit. | `CC 31`, `TR 10`, `TR 22` |
| **FR-86** | **A fake lives once, in a support target, and keeps production semantics.** A test double must fail where production fails, refuse what production refuses, record the whole request and never make an operation look safer or simpler than production; no private fake of a shared protocol lives inside a test file. | `LSP 11`, `TR 5` |
| **FR-87** | **Every interface with more than one implementation has one parameterised contract suite.** The production conformer, each fake and each in-memory implementation must run the same suite, named `<Protocol>ContractTests`; a new conformer joins the suite's subject list in the same commit, and a conformer that would stub a requirement means the protocol is split. | `LSP 10`, `ISP 16`, `TR 6` |
| **FR-88** | **A rule implemented in two languages has one case table both run.** A JavaScript host standing in for a Swift bridge must run one shared JSON fixture of requests, expected answers and expected failures that a Swift test also runs against the production bridge; behaviour production lacks must not be in the host and behaviour production has must not be missing. | `LSP 12`, `TR 7` |
| **FR-89** | **Tests do not sleep.** Test code must contain no `Task.sleep`, `Thread.sleep`, `usleep`, `sleep` or `setTimeout` used as a delay; waiting is awaiting the task or advancing the `ManualClock`, and the one exception is `awaitCondition` for a platform event the test does not own, with a deadline and a failure message. | `TR 8`, `CC 34` |
| **FR-90** | **Tests are hermetic and build production types through the same initialisers.** A test must construct the type under test with a private `UserDefaults(suiteName:)`, a temporary folder, a fake clock and fakes from the support target, and must never touch `UserDefaults.standard`, the real Caches or Application Support folder, the keychain (one real-keychain platform test per target excepted), the network, a shared singleton or the wall clock. | `TR 9`, `DIP 17`, `CC 34` |
| **FR-91** | **Assertions are on typed values.** A test must assert cases, numbers and structures, never message text, `localizedDescription`, `errorMessage` or source text; a string-catalogue test asserts the wording of each case once, no test reads a `.swift` file or navigates the repository through `#filePath`, and module resources are read through the module's bundle. | `TR 11`, `TR 12`, `CC 33` |
| **FR-92** | **Correctness tests assert counts, not elapsed time.** Budgets of nodes, rows or steps must replace seconds in correctness tests; time budgets live in the opt-in benchmark files and record numbers. | `TR 13` |
| **FR-93** | **A skip names a missing platform capability.** `XCTSkip` is for an OS version, an installed voice, hardware or a volume property, with the reason in one constant; a skip because a race did not happen is a defect in the test, the skip count may not rise, and Node real-plugin cases fail when unbuilt in CI. | `TR 14` |
| **FR-94** | **Characterise before moving; regress after fixing.** A commit that moves behaviour must be preceded by a commit that pins it and is green on the old code (touching no `Sources/`); every fixed defect gets a regression test named for the behaviour that fails on the commit before the fix, with the defect ID in the commit message. | `TR 15`, `TR 16`, `CC 35` |
| **FR-95** | **Every persisted format has golden fixtures.** Each persisted format must have a checked-in fixture per shipped version, a round-trip test, an unknown-field preservation test, a corrupt-file test showing the file is moved aside, and an explicit date and number encoding. | `TR 17` |
| **FR-96** | **Platform behaviour is tested where it runs; each extracted responsibility is tested alone.** TextKit, PencilKit, PDFKit gesture and WebKit behaviour must run on macOS in the package or on the iPad simulator hosted; if UIKit is needed to test a rule, the rule moves out of the view. A split is finished only when each extracted type has a test that constructs it without a window, a `WorkspaceModel`, a real vault, a `PDFView` or a running WebKit page. | `TR 18`, `SRP 20` |
| **FR-97** | **Every reader and writer has a failure-injection test.** Each reader and writer must have a test with a failing file access (`FailingVaultFiles`) proving the error surfaces and the file is untouched. | `TR 19` |
| **FR-98** | **Pure planners are tested with values and an injected `now`.** The test of a decision must use no file system and no clock; the planner test imports no file API. | `TR 20` |
| **FR-99** | **Tests run in parallel.** CI must pass with `swift test --parallel`; a test that needs serial execution is a defect (a shared static). | `TR 21` |
| **FR-100** | **CI runs the whole suite on every target on every push.** The workflow must run `swift test`, the hosted iPad suite, the Node suite and the size and rule gates on every push; a red job blocks the push and no session disables a test to pass. | `TR 23`, `CC 35` |

### I Performance and reliability

The owner's goal (2026-10-18) is the fastest and most resource-efficient app Graphite can be: robust, free of defects, fast, fluid and reliable. These rules make that goal checkable. Their sources are that goal, [OBJECTIVE.md](../../OBJECTIVE.md) ("Scale and responsiveness"), the performance invariants `P-01` to `P-16` in [invariants.md](invariants.md), and `FR-69` and `FR-72`, which they extend.

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-101** | **Budgets are numbers in one declaration, and CI enforces them.** One `PerformanceBudgets` declaration must state, with units, the budget of every interaction users feel: keystroke to glyph, Pencil stroke to ink, note open, PDF page turn, tab switch, scroll frame time, vault switch, cold launch, and the memory of an idle app, an open note, a PDF page and each cache and pool. Each budget must have a benchmark (signposts measured by XCTest metrics) that fails CI when it exceeds the budget beyond its stated tolerance; Pencil and latency budgets run on the device job. | Owner goal; OBJECTIVE.md; `P-01`–`P-16` |
| **FR-102** | **Every change is measured before and after.** A cleanup step must record the benchmark results before and after in [progress.md](progress.md); a step that regresses any budget beyond tolerance does not land, whatever structure it improves. | Owner goal; `FR-94` |
| **FR-103** | **The main actor only presents.** File reads and writes, parsing, regular expressions over whole documents, image and PDF encoding, index queries and JavaScript evaluation must not run on the main actor; a main-thread stall reported by the watchdog (`P-09`) is a defect with a regression test. | OBJECTIVE.md; RULES.md "Concurrency, ownership, and performance"; `CC` concurrency findings |
| **FR-104** | **Work is proportional to the change.** Code run per keystroke, stroke, frame, scroll step or file event must touch only the changed range, page, card or file; recomputing a whole document, every page or the whole vault in response to one input is rejected in review. | `FR-69`; `P-02`, `P-06`, `P-08` |
| **FR-105** | **Memory is bounded and given back.** Every cache, pool and history must declare a byte or count budget, release on a memory warning and on a vault switch, and never hold the whole vault's content or every PDF page; large files are read in pieces or memory-mapped, never loaded whole to inspect a header. | `FR-72`; OBJECTIVE.md; `P-01`, `P-04`, `P-11` |
| **FR-106** | **Nothing users see waits for discovery.** The first frame must appear before the vault scan finishes, and opening a document must never await indexing, a plugin, or a network request; each has a budget under `FR-101`. | OBJECTIVE.md ("Opening a document must not wait for a full vault scan") |
| **FR-107** | **Abstractions are free on hot paths.** Per-frame, per-stroke and per-keystroke code must use concrete or generic types, not existentials (`any`) or escaping closures, unless a benchmark shows no cost; release builds keep whole-module and cross-module optimization on, and splitting modules (decision 1) must not turn them off. | Owner goal; decision 1 |
| **FR-108** | **Every crash, hang and loss of work is a defect with a test.** MetricKit diagnostics, watchdog reports and conflict copies feed [defects.md](defects.md); a defect closes only with a regression test that fails before the fix. | Owner goal; `FR-94`; `FR-97` |

### J Features and packages

The owner's direction (2026-10-20): keep Graphite light by building it as a kernel plus features that cost nothing while they are off, and put the code that does not depend on Graphite into packages that can stand as their own repositories.

| Rule | Statement | Sources |
| --- | --- | --- |
| **FR-109** | **A feature that is off does not run.** Every feature outside the kernel (section 9.4) must be built by the composition root only while its switch is on and its registration line exists: while it is off it holds no object, task, timer, observer, file monitor, web view, cache or index work and adds nothing to launch; turning it on or off takes effect without a relaunch and deletes nothing. Its cost while it is on is a budget under `FR-101`. | Owner goal (2026-10-20); OBJECTIVE.md ("each feature can be switched off"); `FR-105`, `FR-106` |
| **FR-110** | **Code that knows nothing of Graphite is a standalone package.** A format reader or writer, or an algorithm over plain values, that compiles without any Graphite module must live in `Packages/<Name>/` with its own tests, fixtures and README, import only Apple system frameworks and other standalone packages, keep members only tests use `internal`, and never write into a vault; CI builds and tests it alone (section 3.5). | Owner goal (2026-10-20); `FR-54` |

### Coverage of the source rules

Each source rule and the `FR` rule that holds it. None is dropped.

| Source rule | Lands in | Source rule | Lands in |
| --- | --- | --- | --- |
| `SRP 1` | FR-01 | `SRP 2` | FR-02 |
| `SRP 3` | FR-03 | `SRP 4` | FR-04 |
| `SRP 5` | FR-05 | `SRP 6` | FR-06 |
| `SRP 7` | FR-07 | `SRP 8` | FR-08 |
| `SRP 9` | FR-09 | `SRP 10` | FR-10 |
| `SRP 11` | FR-11 | `SRP 12` | FR-12 |
| `SRP 13` | FR-13 | `SRP 14` | FR-14 |
| `SRP 15` | FR-15 | `SRP 16` | FR-76 |
| `SRP 17` | FR-77 | `SRP 18` | FR-54 |
| `SRP 19` | FR-16 | `SRP 20` | FR-96 |
| `OCP 1` | FR-17 | `OCP 2` | FR-18 |
| `OCP 3` | FR-19 | `OCP 4` | FR-20 |
| `OCP 5` | FR-21 | `OCP 6` | FR-22 |
| `OCP 7` | FR-23 | `OCP 8` | FR-04 |
| `OCP 9` | FR-03 | `OCP 10` | FR-24 |
| `OCP 11` | FR-11 | `OCP 12` | FR-25 |
| `OCP 13` | FR-28 | `OCP 14` | FR-53 |
| `LSP 1` | FR-10 | `LSP 2` | FR-26 |
| `LSP 3` | FR-27 | `LSP 4` | FR-28 |
| `LSP 5` | FR-59 | `LSP 6` | FR-29 |
| `LSP 7` | FR-30 | `LSP 8` | FR-31 |
| `LSP 9` | FR-47 | `LSP 10` | FR-87 |
| `LSP 11` | FR-86 | `LSP 12` | FR-88 |
| `LSP 13` | FR-32 | `LSP 14` | FR-24 |
| `LSP 15` | FR-33 | `LSP 16` | FR-34 |
| `LSP 17` | FR-35 | `ISP 1` | FR-02 |
| `ISP 2` | FR-02 | `ISP 3` | FR-36 |
| `ISP 4` | FR-37 | `ISP 5` | FR-38 |
| `ISP 6` | FR-39 | `ISP 7` | FR-40 |
| `ISP 8` | FR-41 | `ISP 9` | FR-12 |
| `ISP 10` | FR-42 | `ISP 11` | FR-43 |
| `ISP 12` | FR-37 | `ISP 13` | FR-44 |
| `ISP 14` | FR-44 | `ISP 15` | FR-45 |
| `ISP 16` | FR-87 | `ISP 17` | FR-45 |
| `ISP 18` | FR-16 | `DIP 1` | FR-46 |
| `DIP 2` | FR-47 | `DIP 3` | FR-48 |
| `DIP 4` | FR-49 | `DIP 5` | FR-73 |
| `DIP 6` | FR-74 | `DIP 7` | FR-75 |
| `DIP 8` | FR-50 | `DIP 9` | FR-51 |
| `DIP 10` | FR-52 | `DIP 11` | FR-53 |
| `DIP 12` | FR-72 | `DIP 13` | FR-54 |
| `DIP 14` | FR-55 | `DIP 15` | FR-56 |
| `DIP 16` | FR-57 | `DIP 17` | FR-90 |
| `CC 1` | FR-58 | `CC 2` | FR-59 |
| `CC 3` | FR-60 | `CC 4` | FR-61 |
| `CC 5` | FR-62 | `CC 6` | FR-63 |
| `CC 7` | FR-64 | `CC 8` | FR-11 |
| `CC 9` | FR-65 | `CC 10` | FR-66 |
| `CC 11` | FR-67 | `CC 12` | FR-12 |
| `CC 13` | FR-10 | `CC 14` | FR-06 |
| `CC 15` | FR-55 | `CC 16` | FR-68 |
| `CC 17` | FR-76 | `CC 18` | FR-08 |
| `CC 19` | FR-69 | `CC 20` | FR-73 |
| `CC 21` | FR-28 | `CC 22` | FR-78 |
| `CC 23` | FR-79 | `CC 24` | FR-80 |
| `CC 25` | FR-81 | `CC 26` | FR-82 |
| `CC 27` | FR-77 | `CC 28` | FR-70 |
| `CC 29` | FR-71 | `CC 30` | FR-72 |
| `CC 31` | FR-85 | `CC 32` | FR-83 |
| `CC 33` | FR-91 | `CC 34` | FR-89, FR-90 |
| `CC 35` | FR-94, FR-100 | `TR 1` | FR-83 |
| `TR 2` | FR-83 | `TR 3` | FR-84 |
| `TR 4` | FR-32 | `TR 5` | FR-86 |
| `TR 6` | FR-87 | `TR 7` | FR-88 |
| `TR 8` | FR-89 | `TR 9` | FR-90 |
| `TR 10` | FR-85 | `TR 11` | FR-91 |
| `TR 12` | FR-91 | `TR 13` | FR-92 |
| `TR 14` | FR-93 | `TR 15` | FR-94 |
| `TR 16` | FR-94 | `TR 17` | FR-95 |
| `TR 18` | FR-96 | `TR 19` | FR-97 |
| `TR 20` | FR-98 | `TR 21` | FR-99 |
| `TR 22` | FR-85 | `TR 23` | FR-100 |

### Review checklist

Every change answers these questions. "Yes" is the passing answer; a "no" needs a recorded reason in the pull request or blocks the change. A question that does not apply to the diff is answered "not touched".

1. Does every new or changed class own one aggregate and one kind of work, with 15 or fewer stored properties or a recorded reason, and does a controller that serves several kinds of work hold one active value of the current kind? (`FR-01`, `FR-14`)
2. Does every view, model and helper receive the narrow model or capability it uses, with `WorkspaceModel`, `CommunityPluginHost` and `PDFSession` stored only by the composition root and the scene? (`FR-02`, `FR-36`, `FR-41`)
3. Does the change leave `WorkspaceModel`, `openVault`, the root view and the composition root without a new stored property, feature-named call or reset line? (`FR-03`, `FR-04`)
4. Is every decision (what to insert, which range, which retry) a pure function with a test that builds it from plain values, with the I/O in a separate type? (`FR-05`, `FR-98`)
5. Do UI files avoid I/O, sleeps, the pasteboard, parsing and rule decisions, calling one model method per event, with autosave and release owned by a model rather than a hidden view? (`FR-07`, `FR-09`)
6. Do `body`, getters, predicates, view initialisers and `updateUIView` write no state, start no task and touch no disk? (`FR-08`)
7. For every rule the change classifies, resolves or rewrites, did you search for its owner and call it, or add a parity test for a performance mirror? (`FR-10`, `FR-34`)
8. Are flows with more than two states enums changed through intent methods, are outcomes returned or thrown rather than left in fields, and does state advance only after the operation succeeds? (`FR-11`, `FR-12`)
9. Is derived state computed from one place, with no follow-up call that a caller must remember? (`FR-13`)
10. Is a settings type limited to one feature area and one scope, with per-vault data kept out of the per-device store? (`FR-15`, `FR-73`)
11. For a new kind, panel, command, creatable item or format: is it one enum case plus one descriptor registered by the owning module, derived everywhere else, with no `default:` over an own enum and no equality test on a kind? (`FR-17`, `FR-18`, `FR-19`, `FR-23`)
12. Are external strings mapped once to an enum with `unknown(raw)`, shared vocabularies generated from one declaration, and an unknown operation answered with a failure? (`FR-20`, `FR-21`, `FR-22`, `FR-24`)
13. Do platform variants of one name serve the same inputs, with shared decisions in a shared type, `#if os` blocks holding platform calls only, and one contract suite run on both platforms? (`FR-06`, `FR-26`, `FR-87`)
14. Do equality, hashing and identity cover every behavioural input and come from structured content, never from display text, a hash value or an index? (`FR-27`, `FR-28`)
15. Is every success answer computed from the returned outcomes, and is every refused step reported and handled by one helper? (`FR-29`, `FR-35`)
16. Does every new protocol have two conformers or a stated test need, a "why" comment, at most 7 members and a documented contract that all conformers meet, with no forwarding default and no no-op body? (`FR-30`, `FR-31`, `FR-37`, `FR-53`)
17. Does each function that stops, cancels, clears or resets state its scope in its name or signature? (`FR-33`)
18. Are reading and destroying separate capabilities, and do sessions take `DocumentFileAccess` rather than `VaultStore` or `VaultIndex`? (`FR-38`, `FR-39`)
19. Are model fields with an invariant `private(set)`, with no view assigning a model field, no settable closure slot on a platform view or shared service, and registrations keyed by identity? (`FR-40`, `FR-42`, `FR-43`)
20. Does structured data that crosses a boundary use a `Codable` type decoded once, and is every user-visible file read and written through the same type? (`FR-44`, `FR-45`)
21. Is every collaborator built in the composition root and passed in, with no default argument constructing I/O, no singleton, no mutable static and the passed instance the only one used? (`FR-46`, `FR-47`, `FR-48`, `FR-49`)
22. Do time, calendar and randomness come from the injected source, with preferences passed as values into per-touch, per-frame and layout code? (`FR-50`, `FR-75`)
23. Is file and network I/O in adapters only, platform singletons at the edge, and does each module import only what its row in section 3 allows? (`FR-51`, `FR-52`, `FR-54`)
24. Does domain code return typed facts, with one presenter and the string catalogue producing every user-visible word? (`FR-55`, `FR-63`, `FR-64`)
25. Are launch modes compositions, with no test hook, test-only mode or measuring tool in a production type? (`FR-32`, `FR-56`)
26. Does every `try?` carry a same-line reason, is every failed read distinct from an empty result, does every destructive step stop when its safety copy fails, and is unreadable data kept? (`FR-58`, `FR-59`, `FR-60`, `FR-61`)
27. Do constant patterns use `StaticPattern`, do parsers go through the bounded entry, and does no file-handling code trap? (`FR-62`, `FR-68`, `FR-71`)
28. Does the change await completion instead of sleeping, give every task, timer and observer an owner that ends it, and use the shared primitives for debounce, latest answer and timeout? (`FR-65`, `FR-66`, `FR-67`)
29. Are hot paths proportional to the change and off the main actor when the work is not UI work? (`FR-69`)
30. Does every concurrency escape sit in the module's allow-listed file with its invariant, and is every cache owned, bounded, truthful in its comment and reached by the release duty? (`FR-70`, `FR-72`)
31. Is every persisted key declared once in the registry, with no command or model writing a key to change what a view shows? (`FR-73`, `FR-74`, `FR-24`)
32. Are functions at most 40 code lines (or reviewed), nesting at most 5, parameters at most 6, lines at most 160 characters, and each file one concept named after it? (`FR-76`, `FR-77`)
33. Are durations, caps and sizes named constants with units, comments present-tense rules, names full words, embedded code in resource files, and is every new declaration used by production code? (`FR-78`, `FR-79`, `FR-80`, `FR-81`, `FR-82`)
34. For plugin runtime JavaScript: one object per file, every field declared in the constructor, handlers registered through the router, the host channel passed in, no page-wide patch outside the named file? (`FR-16`, `FR-25`, `FR-57`)
35. Are tests discovered, named after the production type, in the owning module's target, asserting typed values, without sleeps, `UserDefaults.standard`, the real keychain, the network or the wall clock? (`FR-83`, `FR-84`, `FR-89`, `FR-90`, `FR-91`, `FR-92`, `FR-93`)
36. Do fakes live once in a support target, keep production semantics and run the contract suite of the interface they replace, and is a cross-language rule run from one shared case table? (`FR-85`, `FR-86`, `FR-87`, `FR-88`)
37. Is a moved behaviour preceded by a pin commit that is green on the old code, a fixed defect covered by a regression test named for the rule, every persisted format covered by golden fixtures, and every reader and writer covered by a failure-injection test? (`FR-94`, `FR-95`, `FR-97`)
38. Is each extracted responsibility tested alone, and is platform behaviour tested where it runs? (`FR-96`)
39. Does CI pass on every target with parallel tests, the hosted iPad suite, the Node suite, `size-report` and the rule ratchet? (`FR-99`, `FR-100`)
40. Did the change name its invariants from [invariants.md](invariants.md) (by prefix and number) and keep their tests green? (`FR-94`, `FR-95`)
41. Are the benchmark results before and after recorded, and is every budget within tolerance? (`FR-101`, `FR-102`)
42. Does anything new run on the main actor that reads files, parses, encodes, queries the index or evaluates JavaScript? (`FR-103`, `FR-106`)
43. Does the new code's work per input, and its memory, scale with the change rather than the document or vault, with a declared budget for every cache? (`FR-104`, `FR-105`)
44. Does any hot path use an existential or escaping closure without a benchmark, or does the change turn off an optimization? (`FR-107`)
45. Is everything the change adds to a feature built only while that feature is on, released when it is turned off, and absent from launch while it is off? (`FR-109`)
46. Does new code that needs no Graphite type live in a standalone package, and does nothing under `Packages/` import a Graphite module? (`FR-110`)

## 12. Migration plan

### 12.1 How the plan works

1. **Strangle, never big-bang.** A new type is built beside the old one, callers move one at a time, and the old type is deleted in the same phase once its last caller has moved. No forwarding method outlives the phase that created it, except the few named bridges that Phase 14 deletes (`errorMessage`, `isRuntimeRunning`). `RULES.md` forbids layers that only forward.
2. **Every commit builds and runs on iPad and Mac.** Each phase ends with a product that builds for the iPad simulator and macOS, launches, and passes its exit check. A commit either moves code without changing behaviour or changes behaviour for one named defect or decision, never both (`FR-94`).
3. **Pin before moving.** The first step of every phase is the characterization tests for the invariant rows (`invariants.md`) that the phase's code carries and that have no test today (the "No test today" rows, [195 in all](invariants.md)). Phase 0 pins priority 1 and 2 (persisted formats and keys, security: 80 rows); each later phase pins its own priority 3 rows (behaviour with data consequences) before it moves their code.
4. **The ratchet.** Phase 1 adds `scripts/check-rules.py` and `scripts/rule-baselines.json`. Each gate is a grep or count from a rule's check, recorded at b13dec3; CI fails when a count rises above its baseline, and a baseline only goes down. Each phase lowers the gates it names; Phase 14 sets them to their rule targets.
5. **Local runs.** Graphite sits in iCloud's Desktop, where code signing fails; local runs use `swift test --scratch-path` and `xcodebuild -derivedDataPath` outside the checkout. CI runs from a clean clone.
6. **One branch per wave** with a descriptive name; the owner commits. The order of phases follows the dependency order of the extractions: tests and tooling, then the composition root and device state, then Core rule owners, then errors, then module boundaries, then the workspace, then features from the smallest to the one the owner cares most about (the editor, last, with a benchmark gate).
7. **A feature leaves its phase switchable at no cost.** From Phase 6 on, the phase that moves a feature into its module also makes it meet `FR-109`: its exit check includes that feature's `FeatureSwitchTests` and the launch and memory increments it adds.

### 12.2 The ratchet gates

Baselines are the audit's counts; `check-rules.py --record` measures the exact numbers on b13dec3 and the numbers below, taken with plain `grep` on the snapshot, differ by a few from the audit's (for example 630 uncommented `try?` against 628), because the regular expressions differ.

| Gate | Check | Baseline | Target | Lowered in |
| --- | --- | --- | --- | --- |
| `wait-until-copies` | `func waitUntil` in `Tests`, `App/Tests` | 41 | 1 | 1 |
| `user-defaults-standard-in-tests` | `UserDefaults.standard` in `Tests`, `App/Tests` | 98 (audit 101) | 0 | 2 |
| `user-defaults-standard-in-sources` | `UserDefaults.standard` in `Sources` | 27 | 0 outside `App/Composition` | 2 |
| `app-storage-literals` | `@AppStorage("` literal key | 7 | 0 | 2 |
| `shared-singletons` | `static let shared` | 11 | 0 outside the allow-list | 2 |
| `workspace-model-consumers` | `: WorkspaceModel` stored declarations and parameters | 71 and 24 (audit 69 and 17) | composition root and scene only | 6 |
| `core-io` | `FileManager`, `URLSession`, keychain, Application Support in `GraphiteCore` | 9 files | 0 | 5 |
| `graphite-error-prose` | `GraphiteError.unavailable("`, `.invalidFile("` and `.oversized("` with a string literal | 84 | 0 | 4 |
| `localized-description-in-ui` | `localizedDescription` in `Sources/GraphiteUI` | 172 | presenter and `Logger` only | 4 |
| `empty-catch` | `catch { }` | 6 | 0 | 4 |
| `document-parsing` | `Document(parsing` | 5 | 1 | 3 |
| `constant-pattern-try` | `try[?!] NSRegularExpression` | 93 | user-supplied patterns only | 3 |
| `hash-value-identity` | `hashValue` | 10 | 0 identity uses | 3 |
| `try-uncommented` | `try?` with no `//` on the line | 630 (audit 628) | 0 | 4, then each area, 14 |
| `task-sleep-and-hops` | `Task.sleep`, `asyncAfter` in `Sources` | 50 and 10 (audit 51) | primitives and listed exceptions only | each area, 14 |
| `untyped-dictionaries` | `[String: Any]` and `-> Any` | 132 (ISP 13) | boundary adapters only, decreasing | 9, 4, each area |
| `concurrency-escapes` | `@unchecked Sendable`, `nonisolated(unsafe)`, `assumeIsolated` | 20, 4, 41 | allow-listed files only | each area, 14 |
| `test-round-names` | Test files named `Fix`, `Regression`, `Handoff` | 31 | 0 | each area, 12 |
| `size-report` | `python3 scripts/size-report.py` | exit 0 | exit 0, no new function over 40 code lines | 1 |
| `module-imports` | `scripts/check-imports.py` against section 3.2 | passes for the existing five modules | passes for every module | 5 to 12 |

### 12.3 Phase overview

| Phase | Name | Depends on | Exit criterion (checked by a script or a test) | Files touched (rough) |
| --- | --- | --- | --- | --- |
| 0 | Fix the defects that reach users, and pin behaviour | none | 38 regression tests and the priority 1 and 2 pins exist and pass; `scripts/check-defect-tests.py` and `scripts/check-invariant-pins.py` exit 0 | 35 production, 60 test, 9 fixture folders |
| 1 | Test and tooling foundation | 0 | CI workflow green on six jobs; `GraphiteTestSupport` and `GraphiteFixtures` in `Package.swift`; `check-rules.py` and `size-report.py` exit 0; one `waitUntil` | 25 new, 100 test files mechanically |
| 2 | Composition root and device state | 1 | Gates `user-defaults-standard-*`, `app-storage-literals`, `shared-singletons` at target; the golden key test passes | 55 production, 60 test |
| 3 | One owner per rule, in Core | 1 | `LinkResolutionContractTests` and `MarkdownRuleParityTests` pass with no expected-divergence rows; gates `document-parsing`, `constant-pattern-try`, `hash-value-identity` at target | 35 Core, 15 UI, 25 test |
| 4 | Typed errors, one presenter, no silent failures | 3 | Gates `graphite-error-prose`, `empty-catch`, `localized-description-in-ui` at target; failure-injection tests pass | 80 production, 40 test |
| 5 | Module boundaries and ports | 2, 4 | `GraphiteStorage`, `GraphiteDesign`, `GraphiteMarkdownRendering` in `Package.swift`; gate `core-io` = 0; `check-imports.py` passes; `Packages/NotebookImport` builds and tests alone | 60 files move, 120 change imports |
| 6 | Workspace decomposition and registries | 5 | `WorkspaceModel` at most 15 stored properties; `FeatureRegistryTests` pass; gate `workspace-model-consumers` at target; the kernel-only composition launches; `FeatureSwitchTests` pass for the features moved so far | 90 production |
| 7 | Canvas, graph and map, Bases | 6 | `GraphiteCanvas`, `GraphiteGraphAndMap`, `GraphiteBases` build and pass `check-imports.py`; their contract suites pass | 45 production, 40 test |
| 8 | Read Aloud | 6 | `ReadAloudSpeechPlaybackContractTests` passes for all adapters; no `reader.session.` in views; `GraphiteReadAloud` builds | 35 production, 30 test |
| 9 | Plugins and runtime | 6 | Generated message files match (`--check`); the Node suite runs the shared case table; `CommunityPluginHost` deleted | 25 Swift, 45 JavaScript, 30 test |
| 10 | PDF and recording | 6 | `PDFSession` and `RecordingController` replaced; `adoptRecording` gone; contract suites pass | 40 production, 25 test |
| 11 | Ink | 6, 10 | Format contract suite runs PNG, SVG and PDF; `HistoryCanvasView` at most 15 stored properties; hosted Pencil tests pass | 35 production, 25 test |
| 12 | Editor and reading | 3, 6, 7 | `EditorSessionDutiesContractTests` pass on package (Mac) and hosted (iPad); typing, scrolling and tab-switch benchmarks not worse than b13dec3 | 70 production, 40 test |
| 13 | Design system and strings | 12 | Contrast tests pass; no raw colour or size literal in a view; no literal sentence outside the catalogue | all view files, mechanical |
| 14 | Delete what the new structure replaced | 13 | `check-rules.py --final` exits 0 with every baseline at its target; dead-code scan reports nothing; `GraphiteUI` absent from `Package.swift` | 30 files, mostly deletions |
| 15 | Algorithms, measured | 14 (a budget that fails earlier is a defect, fixed when found) | Every `PerformanceBudgets` entry has a device benchmark that passes nightly; every change has its before-and-after row | Decided by the profile |

### 12.4 Phase 0: fix the defects that reach users, and pin behaviour

**Goal.** Ship the 38 defects of "Fix before the cleanup starts" ([defects.md](defects.md)), each with a regression test that fails on b13dec3 and passes on the fix, and pin the invariants the first refactors touch, so that every later characterization test pins correct behaviour. This phase changes production code only where a defect fix is the point (`TR 15`, `TR 16`, `FR-94`).

**Steps.**
1. Baseline (`T-01`): run the three suites once and record pass, skip and failure counts per target and the 29 skipped sites in `Docs/Coverage.md`; run `swift test --parallel` and record what fails (`CC-ARCH-09`).
2. Make the tests tell the truth (`T-02`, `T-03`): the Core test that enumerates the gitignored `Tests/test_vault` becomes a constant corpus; the Node host compares snapshot text, refuses read-only notes, throws on rename onto a taken name and refuses `vault.write` without an expectation (`LSP-RUNTIME-01`, `LSP-PLUGIN-01`).
3. The five High defects first (`T-04`), each fixed by the smallest change: `BUG-SHELL-03` (reply `false` and present the alert, or write separate copies, then quit), `BUG-MDCORE-01` (route the one unguarded `Document(parsing:)` through the nesting guard), `BUG-CANVAS-01` (commit pending text before `undo()` and `redo()`), `BUG-VOICE-V01` (an unreadable pronunciation file is never replaced by the one new entry), `BUG-RUNTIME-01` (one `SnapshotEditor` per note path).
4. The 33 Confirmed Medium defects (`T-05`), grouped by area so each area's tests land together: `BUG-SHELL-01`; `BUG-EDITOR-01`, `-02`, `-04`; `BUG-READING-01`, `-02`, `-03`; `BUG-MDCORE-02`, `-04`; `BUG-VAULT-01`, `-02`; `BUG-BASES-03`; `BUG-CANVAS-02`, `-03`; `BUG-INK-01`, `-02`, `-03`; `BUG-LECTURE-01`; `BUG-VOICE-01`, `-03`, `-04`, `-05`, `-07`, `-08`, `-10`; `BUG-PLUGIN-01`, `-02`, `-03`, `-04`, `-06`; `BUG-RUNTIME-02`, `-03`; `BUG-ARCH-07`. Where [testing.md](testing.md) 5.1 marks a test "seam", the fix is made through the production entry point now and the test moves to the seam when that phase lands. Product decisions inside fixes (owner question 11) are settled before the step starts.
5. Persisted identifiers and formats (`T-06`, `T-09`): golden tests of keys, defaults and paths written against literal strings; golden fixtures for drawing PNG, SVG and PDF, PDF annotations, `.base`, `.canvas`, `bookmarks.json`, `community-plugins.json` generated once from the current writers, reviewed byte by byte, committed.
6. Corpora (`T-07`, `T-08`, `T-11`): one fixture vault and a table of (source, target, expected) run against all link resolvers, one Markdown corpus classified by every consumer, Bases evaluator tables in a fixed time zone; each divergence is a named row tagged with its defect.
7. Workspace invariants (`T-10`) and the unpinned high-value rows of EDITOR, LECTURE, VOICE, PLUGIN (`T-12`).

**Invariants it keeps green.** Every row with a test today; the (defect) rows get regression tests, never characterization of the defective behaviour.

**Exit criterion.** (a) `scripts/check-defect-tests.py` (new in this phase) reads the 38 IDs from `defects.md`, finds each in the `defect | test` table of `Docs/Coverage.md`, and verifies the named test exists and passes; (b) `scripts/check-invariant-pins.py` (new in this phase) reads `invariants.md` and verifies that every priority 1 and 2 row ID appears in the `Pins:` doc comment of a passing test; (c) `swift test`, the hosted iPad suite and the Node suite pass. **Size.** About 35 production files, 60 test files, 9 fixture folders.

### 12.5 Phase 1: test and tooling foundation

**Goal.** Make every later phase checkable: shared test support, hermetic tests, an injected clock, CI, size report and dead-code scan in CI, and the rule ratchet.

**Steps.**
1. `GraphiteTestSupport` and `GraphiteFixtures` in `Package.swift` and the project; move `TestConflictVersionStore` as `FakeConflictVersionStore`, fix its two divergences, add `ConflictVersionStoreContractTests` (`T-13`, `LSP-VAULT-02`, `LSP-ARCH-03`).
2. `TemporaryVault` and `IsolatedDeviceState`; replace the four snapshot-and-restore `setUp` pairs, the `makeVault` copies and direct `temporaryDirectory` use (`T-14`, `CC-SHELL-09`); until Phase 2 the helper wraps a suite and models read it through their existing `UserDefaults` parameters.
3. `ApplicationClock` in Core with `LiveApplicationClock`, `ManualClock` and `awaitCondition`; one `waitUntil` replaces the 41 declarations; inject the clock into canvas autosave, editor jump windows, PDF save back-off and the external-change debounce first, then convert their sleeps (`T-15`, `DIP-CANVAS-04`, `DIP-EDITOR-03`, `DIP-SHELL-05`, `CC-SHELL-02`).
4. `LaunchMode` parsed once in `GraphiteApp.init`; `.hostedTests` selects no vault restore, no diagnostics, isolated defaults, temporary `Caches` and `Application Support` (`T-16`, `ARCH-INV-17`, `DIP-ARCH-01`); the hosted target becomes a synchronised folder and the 18 doubly compiled files move to one shared folder (`T-17`).
5. CI (`T-35`): the six jobs of [testing.md](testing.md) 4.8 (`swift-test-macos` with `--parallel`, `hosted-ipad`, `runtime-node`, `size-report`, `registration-check`, `nightly`), the skip-count gate and the Node real-plugin gate; the host is owner question 9.
6. Tooling: `scripts/check-rules.py` (the ratchet of section 12.2 and `--coverage` for section 11), `scripts/check-imports.py` (section 3.2 over folders), SwiftLint with `function_parameter_count` 6 and line length 160, ESLint and the formatter for the runtime scripts, the allow-list files for statics and concurrency escapes, and a dead-code scan (Periphery or an equivalent script) with its baseline (`CC 26`, `FR-82`).

**Invariants it keeps green.** All Phase 0 pins. **Exit criterion.** The CI workflow exists and its six jobs pass on a clean clone; `grep -rn 'func waitUntil' Tests App/Tests` returns one hit; `Package.swift` lists `GraphiteTestSupport` and `GraphiteFixtures`; `scripts/check-rules.py` and `python3 scripts/size-report.py` exit 0; the dead-code baseline and the skip count are recorded. **Size.** About 25 new files (scripts, workflow, support) and 100 test files touched mechanically (45 UI, 18 Index, 14 Apple, 23 hosted).

### 12.6 Phase 2: composition root and device state

**Goal.** One place builds the graph and one registry owns every persisted key, so that tests are isolated and vault removal forgets everything (`DIP-ARCH-01`, `DIP-ARCH-03`, `DIP-ARCH-04`, `DIP-SHELL-01`, `DIP-SHELL-02`).

**Steps.**
1. `DeviceStateKey` registry with the exact key names of section 7.2 and golden tests per key; route `GraphitePreferences`, `VaultLibrary`, the workspace keys and every `@AppStorage` site through it without changing names, defaults or encodings (ARCH step 2, `CC-VOICE-05`, `CC-INK-09`, `CC-CANVAS-08`).
2. `VaultDeviceMemory` with the five per-vault families and `forgetVault`; fix `BUG-SHELL-02` and `BUG-ARCH-06` by registering folds; give Read Aloud places a per-vault key and read the old global keys once (`BUG-ARCH-07`, `ST-15`).
3. `AppEnvironment`, `LiveAppEnvironment`, `HostedTestEnvironment`; `WorkspaceModel.init(environment:)` with no default argument; remove the `@State` construction in `GraphiteRootView` and `GraphiteMacScenes`; `SceneLifecycleSaver` replaces the static weak property (ARCH step 3, SHELL step 2).
4. Replace the two `UserDefaults` message channels with model intents (ARCH step 4, `DIP-ARCH-04`).
5. Instance every singleton of section 4.5: `PencilToolbox`, `DocumentPlaceStore`, `ReadingImageCache`, `DrawingEditorDraftStore`, `PaletteToolChoiceObserver`, `CanvasPDFPageRenderer`, `EmbeddedPDFSessions`, `ImageDecodingLimiter`, the `ReadAloudVoices` statics; move the tests that read them to injected instances (`T-18`, `DIP-INK-01`, `CC-INK-15`).

**Invariants it keeps green.** `ST-01` to `ST-27`, `ARCH-INV-01`, `-06`, `-07`, `-08`, `-17`, `SHELL-INV-01` to `-05`. **Exit criterion.** Gates `user-defaults-standard-in-sources` (0 outside `App/Composition`), `user-defaults-standard-in-tests` (0), `app-storage-literals` (0) and `shared-singletons` (allow-list only) at target; the golden key test passes; a launch test asserts a single workspace instance is built. **Size.** About 55 production files and 60 test files.

### 12.7 Phase 3: one owner per rule, in Core

**Goal.** Delete the disagreements: each rule that has several implementations gets one owner with a corpus parity test (`LSP-MDCORE-01`, `LSP-ARCH-01`, `LSP-ARCH-02`, `LSP-VAULT-03`).

**Steps.** (1) Pin the area's priority 3 rows. (2) MDCORE steps 1 to 10: files only (`CC-MDCORE-04`, `-05`), `BoundedMarkdownParser`, the corpus harness, `StaticPattern`, `MarkdownLineSyntax` and its consumers one at a time, the behaviour fixes (`BUG-MDCORE-03` fence indentation limit), `MarkdownBlockLines`, `SortedRangeSet`. (3) VAULT steps 5 and 6: one file per concept, `FrontmatterLocator`. (4) One media vocabulary (`DocumentKind`, `LSP-ARCH-01`, `BUG-ARCH-01`). (5) `VaultLinkResolution` and `LinkNameTable` with `LinkResolutionContractTests` over the fixture vault (`T-21`, `LSP-ARCH-02`, `LSP-VAULT-03`, `LSP-READING-03`, `BUG-VAULT-01`, `BUG-READING-03`, `BUG-ARCH-05`). (6) `FileURLToVaultPath` (`CC-ARCH-08`), `GeneratedFileNames`, `LinkDisplayText` (`BUG-READING-05`), the image-import rule (`LSP-EDITOR-05`), `PDFSignatureInspection` (`LSP-LECTURE-01`), `PolylineGeometry` and PNG constants (`CC-INK-04`), `PageNumberInput.parse` (`BUG-LECTURE-03`), `NoteFolding.headingKey` (`LSP-READING-01`).

**Invariants.** `MD-*`, `LK-*`, `D-*`, `NM-*`, `M-*`, `ARCH-INV-15` and `-16`. **Exit criterion.** `LinkResolutionContractTests` and `MarkdownRuleParityTests` pass with no row marked as an expected divergence; gates `document-parsing` (1), `constant-pattern-try` and `hash-value-identity` at target. **Size.** About 35 Core files, 15 UI call sites, 25 test files.

### 12.8 Phase 4: typed errors, one presenter, no silent failures

**Goal.** Failures are values with facts, one place words them, and none is swallowed (`CC-ARCH-01`, `CC-ARCH-02`, `CC-VAULT-01`, `CC-VAULT-02`).

**Steps.** (1) `StoredRead<Value>` and the typed port errors of section 5.2; `ConfigurationFileState` and throwing readers (VAULT step 4, `BUG-VAULT-02`). (2) Replace `GraphiteError` payloads with typed cases and tests that compare cases (VAULT step 11, `T-33`). (3) Stop swallowing: the vault-switch save (`BUG-ARCH-04`), the Mac quit (`BUG-ARCH-02`), the safety copies (`CC-ARCH-02`, `CC-SHELL-04`, `CC-LECTURE-14`). (4) Per-area error enums (canvas, Bases, recording, PDF, ink, voices) and `WorkspaceAlerts` with the `errorMessage` computed bridge (SHELL step 4). (5) `ErrorPresenter`, the string catalogue skeleton and the catalogue test. (6) `FailingVaultFiles` and a failure-injection test for every reader and writer (`FR-97`).

**Invariants.** `D-*`, `OB-*`, `ARCH-INV-09`, `-12`. **Exit criterion.** Gates `graphite-error-prose` (0), `empty-catch` (0), `localized-description-in-ui` (presenter and `Logger` only) at target; the `try-uncommented` baseline lowered by the sites of this phase; failure-injection tests pass. **Size.** About 80 production files and 40 test files.

### 12.9 Phase 5: module boundaries and ports

**Goal.** Put Core on a diet, create the lower modules and the ports the features need (`SRP-ARCH-02`, `SRP-ARCH-03`, `DIP-ARCH-05`).

**Steps.** (1) Move value types into Core (`SearchSortOrder`, `PaperTemplate`, `PaperSpecification`, `CameraPosition`). (2) Create `GraphiteStorage`: `VaultFiles`, `VaultFileManagement`, `AtomicFileWriter`, `VaultBoundary`, configuration files, recovery stores (VAULT steps 9 and 10, 12; `ISP-VAULT-01`, `ISP-VAULT-02`); `MarkdownSession` and `CanvasSession` move to `DocumentFileAccess`; delete `VaultStore` when it has no members left. (3) VAULT steps 7 and 8: `ScanPhase`, `VaultScanner`, the index query families. (4) `HTTPDownloading` with `URLSessionHTTPDownloader`; `CommunityPluginDeviceStorage`; the bridge's `FileManager` use behind a port. (5) `GraphiteDesign` and `GraphiteMarkdownRendering` (READING step 1 file moves). (6) `GraphiteVoices` benchmark to the benchmark target (`DIP-VOICE-05`). (7) `Package.swift` targets and `scripts/check-imports.py` for the new modules. (8) The first standalone package (section 3.5): the 80 files of `Sources/GraphiteCore/NotebookImport` and their tests move to `Packages/NotebookImport` with its own `Package.swift` and README, Graphite depends on it by path, `check-imports.py` refuses Graphite imports under `Packages/`, and a CI job builds and tests it alone; the candidates of section 3.5 are type-checked and the result recorded.

**Invariants.** `D-*`, `OB-*`, `IX-*`, `ARCH-INV-02`, `-03`. **Exit criterion.** `GraphiteStorage`, `GraphiteDesign`, `GraphiteMarkdownRendering` in `Package.swift`; gate `core-io` = 0; `check-imports.py` passes for the modules that exist; `Packages/NotebookImport` builds and passes its tests alone. **Size.** About 60 files move and 120 change imports.

### 12.10 Phase 6: workspace decomposition and registries

**Goal.** `WorkspaceModel` becomes a router; `OpenVault` is a unit; document kinds, panels and commands come from descriptors (`SRP-SHELL-01`, `SRP-SHELL-02`, `OCP-SHELL-01`, `ISP-SHELL-01`).

**Steps** (SHELL steps 5 to 13, ARCH steps 7 to 9). (1) Extract the self-contained extensions into models: `ConflictVersionTracker`, `VaultAppearanceModel`, `BookmarksModel`, `FileRecoveryModel`. (2) `SearchModel`, `VaultIndexingController`, `ExternalChangeCoordinator`, `VaultFileList`. (3) The write workflows with one `afterWrite(paths:)` hook; a drawing request captures its `FolderAccess` (`BUG-ARCH-03`). (4) `TabWorkspace` with `DocumentKindDescriptor` and `DocumentSession`; every `switch` over `DocumentKind` becomes exhaustive (`OCP-SHELL-01`, `OCP-ARCH-01`). (5) `OpenVault`, `VaultSwitcher`, the lifecycle observer protocols (`SRP-SHELL-02`, `OCP-ARCH-03`); registered observers replace the 8-store fan-out. (6) `WorkspaceCommandCatalogue`, `CreationCatalogue`, panel descriptors, `PresentationRouter`, `WorkspaceWindowLayout`. (7) Narrow views starting with leaf views (`TabSwitcher`, `SearchResultRow`, `VaultItemDragPreview`, `ConflictVersionsBanner`, settings pages); split `GraphiteRootView` and `VaultSidebar`; `BUG-SHELL-04` fixed by a reveal intent. (8) `PluginEditorAccess`, `PluginFileOperations`, `PluginPresentation` replace the host's back-reference; `EmbeddedContentRenderers`; `FeatureRegistry` and the registration list. (9) The kernel and the switches (section 9.4): an inventory of what each core plugin builds and runs while it is off; each registration builds its services only while its switch is on and records what it built; switches for the features that have none today (decision 16: search, PDF, notebooks and Pencil drawing, recording, notebook import, community plugins, community themes); the kernel-only composition in the hosted suite; `FeatureSwitchTests`; cold-launch and idle-memory budgets with every feature off and with the default set (`FR-101`).

**Invariants.** `N-*`, `ARCH-INV-08` to `-14`, `SHELL-INV-09`, `-16`, `-25`, `-31`, `-32`. **Exit criterion.** `WorkspaceModel` has at most 15 stored properties (counted by script); gate `workspace-model-consumers` at target; `FeatureRegistryTests` pass; no `default:` over `DocumentKind`, `SidebarPanel`, `InspectorPanel` or `CreationKind`; the vault-switch test asserts the old `OpenVault` is released and no field list exists; the kernel-only composition builds and launches; `FeatureSwitchTests` pass for every core plugin that exists. **Size.** About 90 production files.

### 12.11 Phase 7: canvas, graph and map, Bases

**Goal.** The two smallest features become modules and prove the template (`SRP-CANVAS-01`, `SRP-BASES-01`, `SRP-BASES-02`).

**Steps.** CANVAS steps 1 to 15 (golden round trips, `CanvasSchema`, typed failures, `BUG-CANVAS-01` structure, `CanvasGroupLabelLayout`, `CanvasGesture`, the `CanvasSession` split, injected preferences, `CanvasCardContentLoader`, `CanvasFileCardKind`, `BUG-CANVAS-02`, `-03`, `-04`, `-05`, `-06`, `VaultGraphProvider`). BASES steps 1 to 15 (contract suite first, required provider, link kind and `BaseRecordLookup`, `BaseViewOptionKey`, throwing provider, the `BaseEvaluator` split with `BaseFunctionName` and `BaseMethodName`, clock and calendar, the `BaseDocumentModel` split behind `BaseRecordSource` over `DocumentFileAccess`, typed problems, `BaseViewKind` descriptors, `BaseRemoteImageSession`, YAML writer files, test renames). Then the `GraphiteCanvas`, `GraphiteGraphAndMap` and `GraphiteBases` targets and registration lines.

**Invariants.** `C-*`, `B-*`, `G-*`, `CANVAS-INV-01` to `-28`, `BASES-INV-01` to `-37`. **Exit criterion.** The three modules build alone (`swift build --target …`) and pass `check-imports.py`; `BaseRecordProviderContractTests` and `DocumentFileAccessContractTests` run production, fake and in-memory subjects; `CanvasSession` and `BaseDocumentModel` are replaced. **Size.** About 45 production files, 40 test files.

### 12.12 Phase 8: Read Aloud

**Goal.** One transport, one audio-session owner, adapters that report their capabilities (`SRP-VOICE-01`, `LSP-VOICE-01`, `ISP-VOICE-01`).

**Steps.** VOICE steps 1 to 12: pin with the no-new-seam tests, `ReadAloudPreferenceKey` (done in Phase 2, verified), `ReadAloudTransport.stop(scope:)`, `ReadAloudAudioSessionOwner` and route-change handling, the split speech protocol with capabilities, `ReadAloudPlaybackState`, the controller split, main-actor relief, the `ReadAloudDocument` split, `PassageRenderQueue` and cache reconcile, composition-root construction and deletion of the statics, typed notices and Codable pronunciations, `GraphiteVoicesTests` (`T-27`); the `GraphiteReadAloud` target.

**Invariants.** `RA-*`, `REC-*` where Read Aloud stops recording, `VOICE-INV-01` to `-33`. **Exit criterion.** `ReadAloudSpeechPlaybackContractTests` passes for the Apple, neural and scripted subjects; gate `reader.session.` in views = 0; `ReadAloudVoices` and `ReadAloudNowPlaying` statics gone. **Size.** About 35 production files and 30 test files.

### 12.13 Phase 9: plugins and runtime

**Goal.** One typed message schema, a session with a phase enum, and a Node host that cannot disagree with production (`OCP-PLUGIN-01`, `CC-PLUGIN-01`, `LSP-PLUGIN-01`).

**Steps.** PLUGIN steps 1 to 17 and RUNTIME steps 1 to 12: the typed operations and `unknownOperation`; the shared bridge case table (`T-22`); typed store errors; `withTimeout`; the contributions value; the phase enum (`BUG-PLUGIN-01`); the view registry (`BUG-PLUGIN-06`); the remaining parts; `CommunityPluginSession` with the runtime channel and device storage injected (`T-29`); the move outcome (`BUG-PLUGIN-03`); secret store status handling (`BUG-PLUGIN-05`); installers over `HTTPDownloading`; copy page as resources; single theme vocabulary; off-main bridge requests. Runtime: `host-channel.js`, the router, the coalesced notifier, the file splits, `LeafHostState`, `PathWriteQueue`, the CSS layer, the sanitiser allow list. The `GraphitePlugins` target.

**Invariants.** `PL-*`, `SEC-*`, `PLUGIN-INV-01` to `-37`, `RUNTIME-INV-01` to `-28`. **Exit criterion.** `scripts/generate-plugin-messages.py --check` (new in this phase) exits 0 (Swift enums and JavaScript constants match `community-plugin-messages.json`); the Node suite runs the shared case table and ESLint passes; hosted `CommunityPluginHostTests` use `ScriptedRuntimeChannel`; `CommunityPluginHost` is deleted and no code reads `GraphitePluginRuntime` as a registry. **Size.** About 25 Swift files, 45 JavaScript files (the 11 scripts split) and 30 test files.

### 12.14 Phase 10: PDF and recording

**Goal.** The PDF experience and recording stop being god objects (`SRP-LECTURE-01`, `SRP-LECTURE-02`, `SRP-LECTURE-03`).

**Steps.** LECTURE steps 1 to 12: golden tests, `PDFAnnotationKey` and exhaustive `PDFEdit`, one owner per rule, the `PDFPageManager` file split and `PDFEditApplier`, `PDFInkRecorder` (`CC-LECTURE-13`), the coordinator split one collaborator at a time, the session split (`PDFSaveController` behind `PDFFileSaving`, `PDFViewState`, `PDFProtection`, `PDFEditHistory`, `PDFOutlineModel`), `EmbeddedPDFViewerModel` (`BUG-LECTURE-02`), recording (`RecordingStore`, `AudioRecorder` port, deletion of `adoptRecording`, `RecordingSession`, `RecordingFlow`, `BUG-LECTURE-01`), typed reasons and one presenter (`BUG-LECTURE-04`), injected clock and owned tasks, typed diagnostics. The `GraphitePDF` and `GraphiteRecording` targets.

**Invariants.** `PDF-*`, `REC-*`, `LECTURE-INV-01` to `-36`. **Exit criterion.** `PDFAnnotationCoordinator` has at most 10 stored properties and `PDFSession` is replaced; `adoptRecording` has no hit; `PDFFileSavingContractTests` and `RecordingSessionContractTests` pass. **Size.** About 40 production files and 25 test files.

### 12.15 Phase 11: Ink

**Goal.** Pencil code keeps its responsiveness while it loses its inheritance tangle (`SRP-INK-01`, `OCP-INK-01`, `DIP-INK-03`).

**Steps.** INK steps 1 to 14 (the draft background fix `BUG-INK-01` is already shipped in Phase 0): one concept per file, `PencilPreferenceKey`, deduplicated rules, typed menu actions, `CanvasMode` and `PaletteCanvasMode`, injected toolbox and preferences, observers removed with their owners, `InkSelectionEdits`, `DrawingPictureArrangement` (`BUG-INK-03` structure), the `InfiniteCanvasView` split, the `HistoryCanvasView` collaborators in the stated order (`BUG-INK-02` structure), `DrawingEditorSession` with the typed `replaceEmbeds` outcome (`BUG-INK-04`), `DrawingFileFormat` descriptors, tolerant toolbox persistence. The `GraphiteInk` target.

**Invariants.** `INK-*`, `M-*`, `INK-INV-01` to `-33`, palm rejection and hold-to-shape budgets in `P-*`. **Exit criterion.** `DrawingFileFormatContractTests` runs PNG, SVG and PDF; `HistoryCanvasView` has at most 15 stored properties; the hosted Pencil suites (`PencilToolsTests`, `PalmRejectionTouchTests`, `PicturesAndPaperTests`) pass. **Size.** About 35 production files and 25 test files.

### 12.16 Phase 12: editor and reading

**Goal.** The editor coordinators become adapters, the iPad and Mac editors honour one contract, and reading view and Live Preview share their rules; typing and scrolling are not slower than before (`SRP-EDITOR-01`, `LSP-EDITOR-01`, `SRP-READING-01`).

**Steps.** EDITOR steps 1 to 14 (pins; session duties shared by both coordinators; shared pure types; `EditorRunLoopScheduler`; `TextViewEditApplier`; fold state; placement scheduler; the remaining collaborators; `EditorCommandDescriptor`; `LivePreviewBlockKindTraits`; `EditorCaches`; the `MarkdownSession` split; removal of `drawsConcealedReplacements`; paste classification), READING steps 1 to 14 (file moves, fold keys and callout keys finished, `VaultLinkResolution` adoption, `NoteTextEditor` and typed outcomes, `ReadingFileLookup`, `ReadingScrollRestoration`, `ReadingBuildModel`, `NoteAutosave`, `NoteLinksInspectorModel`, narrowed `MarkdownPane`, injected caches), MDCORE steps 11 to 13. The `GraphiteMarkdownEditing` and `GraphiteReading` targets and the shell's markdown composition. Before the first step the `GraphiteBenchmarks` numbers for typing latency, scrolling, tab switching and cold open are recorded in `Docs/Coverage.md`.

**Invariants.** `ED-*`, `MD-*`, `LK-*`, `U-*`, `P-*`, `EDITOR-INV-01` to `-31`, `READING-INV-01` to `-30`. **Exit criterion.** Each coordinator has at most 10 stored properties; `EditorSessionDutiesContractTests` and `TextViewEditApplierContractTests` pass on the package (Mac) and the hosted target (iPad); `scripts/compare-benchmarks.py` (new in this phase) reports no regression against the recorded numbers; `MarkdownPreview.swift` holds one concept per file. **Size.** About 70 production files and 40 test files.

### 12.17 Phase 13: design system and strings

**Goal.** Tokens, a string catalogue, and the style rules at their targets (`CC-SHELL-06`, `CC-VOICE-10`; section 10.3).

**Steps.** (1) `DesignTokens` in `GraphiteDesign`; replace raw colour, size and font literals in views; contrast tests. (2) A `Localizable.xcstrings` per module with plural rules; presenters and views use `LocalizedStringResource`; the catalogue test. (3) Named constants for durations, caps and sizes (`CC 22` sites, about 11 areas). (4) Comments restated, dated and owner-naming comments removed (`CC 24`). (5) Names that break `RULES.md` renamed. (6) Remaining `default:` over own enums, remaining functions over 40 code lines recorded or split, the size register reviewed.

**Invariants.** `TH-*`, `U-*`. **Exit criterion.** Contrast tests pass; no raw colour or size literal in a view file and no literal sentence outside the catalogue (gates added here at 0); no comment matching the dated, owner or "used to" patterns. **Size.** All view files, mechanical.

### 12.18 Phase 14: delete what the new structure replaced

**Goal.** Nothing remains of the scaffolding.

**Steps.** (1) Delete the bridges: the `errorMessage` computed bridge, `isRuntimeRunning`, any `WorkspaceModel` forwarding member, the `DeviceStateKey` legacy readers that migrated (Read Aloud global places) once the migration shipped. (2) Delete `GraphiteUI` (its remaining files belong to `GraphiteShell` or a feature) and the empty folders. (3) Raise every gate to its rule target: `try?` uncommented 0, `task-sleep-and-hops` listed exceptions only, `concurrency-escapes` allow-list only, `untyped-dictionaries` at the boundary adapters. (4) Resolve the old tracker per owner question 6. (5) Promote the size register to a hard gate per owner question 5.

**Invariants.** All. **Exit criterion.** `scripts/check-rules.py --final` exits 0 with every baseline at its target; the dead-code scan reports no unused declaration; `GraphiteUI` is absent from `Package.swift`; CI is green on every job. **Size.** About 30 files, mostly deletions.

### 12.19 Phase 15: algorithms, measured

**Goal.** With the structure clean, make the slow paths fast. It is the third of the owner's three ways to a light app: the structure (Phases 0 to 14), features that cost nothing while they are off (`FR-109`), and the algorithms here (decision 15). A budget that fails before this phase is a defect and is fixed when it is found (`FR-108`); this phase takes the paths that meet their budget and can still be faster or lighter.

**Steps.** (1) Complete `PerformanceBudgets` (`FR-101`): every interaction a person feels and every cache has a number and a device benchmark in the nightly job. (2) Profile each budget's path on the iPad (Time Profiler, Allocations and the signposts' points of interest) and rank the costs by what a person feels. (3) One change per commit, each with its benchmarks before and after (`FR-102`) and the invariants it keeps; the findings that break `FR-104` today are the known starting points (`CC-MDCORE-02`: per-keystroke overlap tests are linear; `CC-CANVAS-09`: whole-collection work on every frame). (4) Record what each budget became in [progress.md](progress.md).

**Invariants.** All, the `P-*` rows above all. **Exit criterion.** Every entry of `PerformanceBudgets` has a device benchmark that passes in the nightly job, and no algorithm change landed without its before-and-after row. **Size.** Decided by the profile.

## 13. Decisions the audit cannot make

Each question says what changes with each answer. The owner answered on 2026-10-18 (decisions 1–3, 6 and 12 in the owner's words; the rest "based on what will be better long term", with the stated goal of the fastest and most resource-efficient app: robust, free of defects, fast, fluid and reliable, and "the stricter the better"). The decisions follow the questions and bind the plan.

1. **Feature modules as SwiftPM targets or as folders?** (a) Targets: the compiler enforces section 3's direction, cross-module internals use the `package` access level, build and test times per module drop, previews and tests of one feature link only what it imports; the cost is access-control work in Phases 5 to 12 and an Xcode project that links package products. (b) Folders inside one target, with `scripts/check-imports.py` enforcing the same table: no access-control churn, but a violation is a CI failure rather than a build error, and the incremental build stays whole-module. Phase 5 builds `GraphiteStorage`, `GraphiteDesign` and `GraphiteMarkdownRendering` as targets under either answer, because the lower modules already are.
2. **Do the Mac and iPhone variants keep parity with the iPad?** The Mac editor serves six duties fewer, `GraphitePDFView` ignores 10 of 15 inputs, canvas editing is UIKit-only, and `BUG-EDITOR-01` to `-04` and `BUG-CANVAS-03` are Mac gaps (`LSP-EDITOR-01`, `LSP-LECTURE-02`, `LSP-CANVAS-02`). (a) Parity: Phases 10 and 12 give the Mac the shared duties, one contract suite runs on both, and Mac canvas editing is built. (b) Diverge by design: a descriptor declares `platformAvailability`, an unsupported input becomes an optional sub-value that exists only where served (`FR-26`), the Mac offers no "New Canvas" (`BUG-CANVAS`, canvas step 12), and the contract suites run per supported platform. iPhone follows the same answer for the features its layout cannot host.
3. **Do the deployment floors stay at iOS 18.0 and macOS 27.0 ([Package.swift:6](../../Package.swift#L6))?** At these floors `@Observable`, `Synchronization.Mutex`, typed throws, `isolated deinit` and the `package` access level are available and the plan uses them. Lowering the iOS floor below 18 removes `Mutex` (the token cache and diagnostics state use locks instead) and changes Phase 1's clock and concurrency primitives; raising a floor removes `#available` branches only.
4. **JavaScript runtime tooling and the shared message schema.** (a) Committed generated files and a CI diff: `community-plugin-messages.json` generates `CommunityPluginOperation.swift` and `community-plugin-operations.js` through a Python script; no build step in Xcode, the Node harness keeps loading classic scripts in order. (b) A SwiftPM build-tool plugin or Xcode run script generates them at build time: no generated file in the repository, but the build depends on the script runtime. (c) A bundler (esbuild) producing one runtime file: modules and imports in the JavaScript, at the cost of a Node build step for every Swift build and a change to how the harness loads scripts. The plan assumes (a).
5. **How strict is `size-report` in CI, and when?** (a) Gate from Phase 1: an item over a threshold without a row in [size-review.md](size-review.md) fails the build, as the script does today. (b) Warn-only until Phase 13, then a gate: no friction during the extractions, but the register can grow. (c) Gate with a ratchet on the count of over-threshold items. The plan assumes (a) for new items and (c) for existing ones.
6. **What happens to the older `Docs/SOLID.md` tracker?** It is dated 2026-09-30 and assesses the working tree of that day. (a) Delete it in Phase 14 and link `Docs/solid/` from `AGENTS.md`. (b) Keep it as a short index that points to `Docs/solid/` and carries no assessment. (c) Keep and update it from this audit by script. The answer decides whether two documents claim a SOLID status of the repository.
7. **Do the Phase 0 defects ship before any refactor?** (a) Yes: each fix is its own commit on `main` (main is alpha), and users get 38 fixes first; Phase 1 starts after the fixes are in. (b) Together with Phase 1: the fixes wait for CI, which makes a regression in a fix visible earlier but delays the High defects (`BUG-SHELL-03` discards unsaved edits on quit) by the length of Phase 1. The plan assumes (a), with the five High defects first.
8. **Where does the hosted suite run: simulator, device, or both?** (a) Simulator in CI on every push, device by hand before a release: the Pencil tests use `SynthesizedTouches`, so pressure, tilt and latency invariants (`INK-*`, `P-*`) cannot be gated. (b) A device in a nightly job: those invariants are gated, at the cost of a connected iPad and a runner that can reach it. The camera, microphone and neural model load never run in the simulator (`NeuralSpeechEngine.swift:80-81`), so those rows stay manual under either answer.
9. **Which CI host?** There is no workflow file today. GitHub Actions on macOS runners, Xcode Cloud, or a script on the owner's Mac. The choice decides the simulator runtime available, whether the iCloud codesign problem applies (it does not on a clean clone), and the format of the six jobs of `T-35`.
10. **Is localisation in scope?** (a) English only: the catalogue holds keys and English values, plural rules apply, nothing else ships. (b) Other languages: translation files, pseudo-localisation tests, and layout checks for long strings enter Phase 13. The structure (section 10.3) is the same under both.
11. **Product decisions that fixes and refactors need.** (a) Setext headings: add them to the outline, anchors, sections and folding, or remove them from the index too (`BUG-MDCORE-04`). (b) A fence indented four or more columns: not a code block in the index and in the editor (`BUG-MDCORE-03`). (c) The Obsidian settings writers: output changes from sorted keys to Obsidian's key order (VAULT step 10), recorded in the release notes. (d) HEIC: one image-format rule (`LSP-EDITOR-05`). (e) Whether a plugin view opened "in the current tab" replaces the tab (`BUG-RUNTIME-03`). (f) The Mac's "New Canvas" offer (`BUG-CANVAS-03`). Each answer decides a test expectation in Phase 0 or the phase of its area.
12. **Will Graphite ever run more than one workspace per process?** Today one iPadOS scene and one Mac window are assumed (`ARCH-INV-08`, [Info.plist:38-42](../../App/Info.plist#L38-L42)). (a) Never: the plan's per-scene objects stay as they are and the environment is process-wide. (b) Stage Manager windows or multiple Mac windows: the environment splits into process services and scene services before Phase 6, the embedded-PDF registry and the Pencil activity become per-scene, and two workspaces on one index file need a lock the index does not have.
13. **Dead-code tool.** Periphery (needs an index build, slow, precise) or a script over symbol references (fast, less precise). Decides the cost of the CI job and the false-positive handling of SwiftUI and `@Observable` members.
14. **Do self-contained parts become their own packages?** (a) Yes: what compiles without Graphite moves to `Packages/<Name>/` with its own tests and README, ready to become its own repository. (b) No: it stays a folder of `GraphiteCore`.
15. **How is the app kept light?** (a) Structure only (Phases 0 to 14). (b) Structure, then measured algorithm work, and features that do not run while they are off.
16. **Which features form the kernel that cannot be switched off?** The plan assumes vault access and storage, the index, the file list, the Markdown note editor and reading view, tabs and windows, and Settings; everything else becomes a switchable feature, including search, PDF, notebooks and Pencil drawing, recording, notebook import, community plugins and community themes. A smaller kernel saves more while features are off and needs more switches; a larger one is less work.

### Decisions (owner, 2026-10-18)

| # | Decision | What it changes in this plan |
| --- | --- | --- |
| 1 | **SwiftPM targets** (a), chosen as better long term. | Section 3's direction is enforced by the compiler; cross-module internals use `package` access. Release builds must keep whole-module and cross-module optimization on so the split costs no runtime speed (`FR-107`); a benchmark before and after the first split confirms it (`FR-102`). |
| 2 | **Parity on Mac and iPhone, except Apple Pencil features** (a). | Phases 10 and 12 give the Mac editor its six missing session duties, `GraphitePDFView` on the Mac all its inputs, and the Mac canvas editing with "New Canvas" (`LSP-EDITOR-01`, `LSP-LECTURE-02`, `LSP-CANVAS-02`, `BUG-EDITOR-01`–`04`, `BUG-CANVAS-03`). One contract suite runs on iPad, iPhone and Mac. Features that need Pencil hardware (pressure, tilt, hover, squeeze, double tap, palm rejection, the Pencil tool palette) stay iPad-only and say so in their descriptor's platform availability (`FR-26`, `FR-37`). |
| 3 | **Deployment floors iOS 27, iPadOS 27 and macOS 27.** | Phase 1 raises `Package.swift` from `.iOS(.v18)` to iOS 27 and the app target with it, removes every `#available` branch below 27, and the plan may use every API of those releases. |
| 4 | **One message schema, TypeScript modules, one bundled runtime file.** | A schema file generates the Swift operation enum and the TypeScript message types (`FR-21`, `FR-22`); the runtime becomes TypeScript modules in `strict` mode, bundled by esbuild into one minified file that is committed; CI rebuilds it and fails on any difference, so a Swift build needs no Node. One file means one parse in the web view: faster plugin start and less memory. The modules replace the global `GraphitePluginRuntime` locator (`SRP-RUNTIME-*`, `OCP-RUNTIME-*`). The Node harness loads the same bundle. |
| 5 | **`size-report` is a gate from Phase 1, for every item.** | Phase 1 reviews all 215 items that have no row yet; from then on an item without a row, or grown by more than a fifth, fails CI. The count of `split planned` rows is a ratchet: it never rises, and each extraction phase lowers it. |
| 6 | **The earlier tracker is merged and removed.** | `Docs/SOLID.md` was merged into this folder ([README](README.md), "Merged from the 2026-09-30 tracker") and deleted; `AGENTS.md` makes this folder binding. Where the two disagreed, the stricter rule stands. |
| 7 | **Phase 0 defects ship before any refactor** (a), the five High defects first. | Each fix is its own commit with a regression test; Phase 1 starts after the 38 fixes are in. |
| 8 | **Both: simulator on every push, device every night.** | The device job gates the Pencil, latency and memory budgets (`INK-*`, `P-*`, `FR-101`) that `SynthesizedTouches` cannot. Camera, microphone and neural-model rows stay manual before a release. |
| 9 | **GitHub Actions**, where the repository already lives. | Hosted macOS runners run `swift test`, the iPad simulator suite, the Node suite, the generated-file diff, `size-report`, the rule ratchet and Periphery on every push; a self-hosted runner on the owner's Mac with the iPad connected runs the nightly device job, from a checkout outside the iCloud-synced Desktop. |
| 10 | **String catalogue now; pseudo-localisation and long-string layout tests in Phase 13.** | Every user-visible string goes through the catalogue with plural rules (`FR-55`); layout is tested with long and right-to-left pseudo-strings so it stays robust; translations ship when the owner picks languages, with no code change. |
| 11 | **Product rules follow CommonMark and Obsidian, one owner each.** | (a) Setext headings are headings everywhere: outline, anchors, sections and folding (`BUG-MDCORE-04`). (b) A fence indented four or more columns is not a fence, in the index and in the editor alike, through one Core fence rule (`BUG-MDCORE-03`, `LSP-MDCORE-01`). (c) The Obsidian settings writers keep Obsidian's key order, so a file Graphite writes differs from Obsidian's only where a value changed. (d) One `PastedImagePolicy` for every import path: PNG and JPEG kept as they are, HEIC converted to JPEG (Obsidian does not show HEIC), everything else to PNG (`LSP-EDITOR-05`). (e) A plugin view opened "in the current tab" replaces that tab's view, as in Obsidian, after its unsaved work is saved (`BUG-RUNTIME-03`). (f) The Mac offers "New Canvas" (decision 2). |
| 12 | **More than one window per process: yes** (b). | Before Phase 6 the environment splits into process services (index, vault library, plugin runtime, voices) and scene services (workspace, tabs, Pencil activity, embedded-PDF registry). Two windows on one vault share one index through a single-writer actor. `ARCH-INV-08` (one scene assumed) is retired by this decision when the split lands. |
| 13 | **Periphery** for dead code. | A CI job on every push, with a reviewed allow-list for SwiftUI and `@Observable` members it cannot see used (`FR-82`). |

### Decisions (owner, 2026-10-20)

| # | Decision | What it changes in this plan |
| --- | --- | --- |
| 14 | **Self-contained parts become packages** (a): "some things can be packaged in a package so we can put it even as its own repo", the Goodnotes and Notability readers first. | Section 3.5 and `FR-110`; Phase 5 step 8 moves the notebook import readers to `Packages/NotebookImport`, and each later candidate moves when it type-checks alone. |
| 15 | **Light by structure, algorithms and features that do not run while off** (b): the structure first, then the algorithms, and "if some plugin (even core) is not there then it doesn't run". | Section 9.4 and `FR-109`; Phase 6 step 9 builds each core plugin only while it is on and adds the kernel-only composition and `FeatureSwitchTests`; every later feature phase keeps its feature switchable at no cost (12.1, point 7); Phase 15 does the measured algorithm work. |
| 16 | **The kernel as proposed:** vault access and storage, the index, the file list, the Markdown note editor and reading view, tabs and windows, and Settings. "Everything else becomes switchable." | Section 9.4, point 1; Phase 6 step 9 adds switches for search, PDF, notebooks and Pencil drawing, recording, notebook import, community plugins and community themes, and `FeatureSwitchTests` covers each. |

## Corrections

Where two audit documents disagree, the snapshot decides. These are the disagreements this document had to settle.

- **Feature module list.** [architecture 7.1](cross-cutting/architecture.md) names eight feature modules and says MapKit is only in `GraphiteBases`. In the snapshot `NotesMapView` ([NotesMapView.swift](../../Sources/GraphiteUI/NotesMapView.swift)) imports MapKit and belongs to the graph and map presentations, not to Bases. This document therefore adds `GraphiteGraphAndMap` (MapKit in two modules), `GraphiteRecording` (the LECTURE blueprint gives recording its own types and ports and no code shared with PDF) and `GraphiteMarkdownRendering` (the editor and the reading view both draw with `CalloutView`, `ReadingImageCache` and the reading text styles, which `SRP-READING-02` records as a library file other areas depend on).
- **Features and the index.** The architecture audit lets features import `GraphiteStorage` and the index read ports; this document forbids both (section 3.3 rule 3) because `ISP-VAULT-01`, `ISP-BASES-01` and `ISP-CANVAS-04` show that consumers need four or five operations, supplied as capabilities.
- **File-access capability.** VAULT says `DocumentFileAccess` is a value of `VaultFiles` methods with no protocol; CANVAS asks for a contract suite shared with `MarkdownSession`; EDITOR proposes `NoteFileStore` (5 operations); BASES proposes `BaseFileAccess`; LECTURE proposes `PDFFileSaving`. Resolution: `DocumentFileAccess` is one struct of four closures with one contract suite (its subjects are the `VaultFiles`-backed value and the in-memory and failing fakes); `NoteFileStore` and `BaseFileAccess` are not created, and `PDFFileSaving` stays because PDF saving also replays and compacts.
- **`OpenVault`.** SHELL describes a value plus a `VaultSwitcher`; ARCH describes an object that holds the indexing controller, debouncer and conflict state. Resolution: a final class holding immutable I/O handles and the vault-scoped models, replaced as a unit, with the switch procedure in `VaultSwitcher`.
- **Names.** SHELL says `VaultIndexing` and `RecordingWorkflow`; ARCH says `VaultIndexingController` and `RecordingCoordinator`. This document uses `VaultIndexingController` and `RecordingWorkflow`. VOICE renames `ReadAloudSpeaking` to `ReadAloudSpeechPlayback`; [testing.md](testing.md) still uses the old name.
- **Test support.** [testing.md](testing.md) 4.1 proposes one `GraphiteTestSupport`; fakes also serve previews (`FR-56`), and a target that imports XCTest cannot ship in a debug preview, so the fakes and value fixtures live in `GraphiteFixtures` (no XCTest) and the XCTest helpers and contract suites in `GraphiteTestSupport`.
- **Counts.** The properties of `CommunityPluginHost` are 63 by recount ([architecture 8.5](cross-cutting/architecture.md)), not 55. Plain greps on the snapshot give 630 uncommented `try?` (audit 628), 98 `UserDefaults.standard` in tests (101), 71 and 24 `WorkspaceModel` consumer declarations (69 and 17) and 20 `@unchecked Sendable` by the rule's pattern (25 by plain text, which includes comments); `check-rules.py --record` fixes the exact numbers in Phase 1 and the baselines use them.
- **Phase 0 size.** [invariants.md](invariants.md) counts 39 defects in scope (the 38 plus `BUG-SHELL-02`); `BUG-SHELL-02` and its alias `BUG-ARCH-06` are fixed with the key registry in Phase 2, so Phase 0 holds 38.
