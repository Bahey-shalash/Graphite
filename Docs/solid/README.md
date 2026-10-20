# SOLID and clean-code standard

Snapshot: b13dec3 (main, 2026-10-18). Current assessment: b13dec3 (no cleanup step has landed; see [progress.md](progress.md)).

This folder is Graphite's standard for structure and code quality: what is wrong and why, what is sound and must be kept, which behaviour must never break, the rules all new code is held to, and the step-by-step plan to get there. Cleanup sessions work from it wave by wave. It replaces the earlier tracker `Docs/SOLID.md` (2026-09-30), which is merged into it (section "Merged from the 2026-09-30 tracker") and removed; [OBJECTIVE.md](../../OBJECTIVE.md) and [RULES.md](../../RULES.md) stay authoritative over it.

## Goal and decisions

**The goal (owner, 2026-10-18): the fastest and most resource-efficient app Graphite can be: robust, free of defects, fast, fluid and reliable. The stricter the standard, the better.** Every rule here serves that goal. Group I of the rules (`FR-101` to `FR-108`) makes it checkable: one table of performance and memory budgets enforced in CI and on a device, every change measured before and after, a main actor that only presents, work proportional to the change, bounded memory, and every crash, hang or loss of work turned into a defect with a regression test.

The owner answered the audit's thirteen questions the same day ([rewrite-foundations.md](rewrite-foundations.md), "Decisions"): feature modules become SwiftPM targets; the Mac and iPhone reach parity with the iPad except for Apple Pencil features; the deployment floors become iOS, iPadOS and macOS 27; the plugin runtime becomes TypeScript modules bundled into one file, with one message schema shared with Swift; `size-report` gates every item from Phase 1; the 38 user-facing defects ship before any refactor; tests run in the simulator on every push and on an iPad every night, through GitHub Actions; Graphite will support several windows per process. The cleanup starts when the owner says go.

On 2026-10-20 the owner added two directions ([rewrite-foundations.md](rewrite-foundations.md), decisions 14 to 16): code that knows nothing of Graphite becomes a standalone package that could be its own repository, the Goodnotes and Notability readers first (section 3.5, `FR-110`); and the app stays light through its structure, then measured algorithm work (Phase 15), and features that do not run at all while they are off, core plugins included (section 9.4, `FR-109`). The kernel that cannot be switched off is vault access and storage, the index, the file list, the Markdown note editor and reading view, tabs and windows, and Settings; everything else becomes switchable (decision 16).

## Current adherence

Graphite is strong at the edges and weak in the middle. The Core value types, file formats and storage contracts are sound: lossless JSON Canvas editing, revision-checked atomic writes, bounded parsers, drawing files that stay ordinary PNG/SVG/PDF, and request-identity guards against stale results are recorded as things to keep. The coordinating layer is not: `WorkspaceModel` holds 86 stored properties over 23 files and 2,695 code lines, 74 views take the whole workspace, there is no composition root (11 `static let shared` singletons, about 91 `UserDefaults` keys with no single owner), `GraphiteUI` is one module with 57% of the production code, and the same rules (link resolution, code fences, display math, fold keys) are written several times and already disagree. No audit rates any principle Strong; 5 of the 78 verdicts are Mostly strong (Liskov in VAULT, CANVAS and INK; interface segregation and dependency inversion in the platform-free Markdown model, MDCORE). Single responsibility is Weak in 8 of the 13 audits and Mixed in the other 5.

The audit records 428 structural findings (33 High, 225 Medium, 170 Low) and 76 distinct defects, of which 70 are confirmed by an independent second reader; 5 are High and none Critical. The test suite has 2,310 XCTest functions and 85 JavaScript tests but no CI, no shared test support, 261 sleeps and 101 uses of the shared `UserDefaults.standard`; 413 invariants are written down; 195 had no test at the audit and 21 still have none after Phase 0. `scripts/size-report.py` finds 284 items over a size threshold, and since Phase 1 every one has a review row (124 one concept, 160 split planned), so the script gates new and grown items. Closing findings and meeting the rules are different measures: [rule-status.md](rule-status.md) reports the rules, [status.md](status.md) the findings, and neither gives a percentage.

A delta audit on 2026-10-19 read every line changed between `b13dec3` and `9040705` (Phase 0, Phase 1 and the notebook library, about 5,000 lines) and added 64 structural findings (26 Medium, 38 Low) and 8 defects (1 High, 4 Medium, 3 Low), recorded in section 9 of each area document and in [defects.md](defects.md#found-after-the-snapshot). New code repeats the old patterns: unowned tasks, settable dependency slots, sentences built in models, and rules written twice. A second delta audit on 2026-10-20 (`9040705` to `5aae924`, about 5,700 lines) added 13 findings in the app and a new area, [Import](areas/import.md), for the Goodnotes and Notability readers (19 findings, 2 latent defects): the readers bound every length and offset, but their memory budgets are too generous for an iPad and they are not wired into the app yet.

## Verdicts at the snapshot

Each area auditor rated each principle (Strong / Mostly strong / Mixed / Weak). Principle names link to the synthesis documents.

| Area | [S](principles/single-responsibility.md) | [O](principles/open-closed.md) | [L](principles/liskov-substitution.md) | [I](principles/interface-segregation.md) | [D](principles/dependency-inversion.md) | [Clean code](principles/clean-code.md) |
| --- | --- | --- | --- | --- | --- | --- |
| [SHELL](areas/shell.md) | Weak | Weak | Mixed | Weak | Weak | Mixed |
| [EDITOR](areas/editor.md) | Weak | Mixed | Weak | Mixed | Mixed | Mixed |
| [READING](areas/reading.md) | Weak | Mixed | Weak | Mixed | Mixed | Mixed |
| [MDCORE](areas/mdcore.md) | Mixed | Mixed | Weak | Mostly strong | Mostly strong | Mixed |
| [VAULT](areas/vault.md) | Mixed | Mixed | Mostly strong | Mixed | Mixed | Mixed |
| [BASES](areas/bases.md) | Mixed | Weak | Weak | Mixed | Mixed | Mixed |
| [CANVAS](areas/canvas.md) | Mixed | Mixed | Mostly strong | Mixed | Mixed | Mixed |
| [INK](areas/ink.md) | Mixed | Mixed | Mostly strong | Mixed | Weak | Mixed |
| [LECTURE](areas/lecture.md) | Weak | Mixed | Mixed | Mixed | Mixed | Mixed |
| [VOICE](areas/voice.md) | Weak | Mixed | Weak | Mixed | Mixed | Mixed |
| [PLUGIN](areas/plugin.md) | Weak | Weak | Mixed | Weak | Mixed | Mixed |
| [RUNTIME](areas/runtime.md) | Weak | Mixed | Mixed | Mixed | Mixed | Mixed |
| [ARCH](cross-cutting/architecture.md) | Weak | Weak | Mixed | Weak | Weak | Mixed |

## Inventory

| Item | Count |
| --- | ---: |
| Code audited | 321 production Swift files, 80,841 code lines, plus 7,287 lines of own JavaScript/CSS/HTML ([metrics.md](metrics.md)) |
| Documents | 32 Markdown documents, about 12,648 source and cross-document links |
| Structural findings | 428: 33 High, 225 Medium, 170 Low |
| Findings by principle | SRP 75, OCP 52, LSP 58, ISP 40, DIP 52, CC 151 |
| Defects | 76 distinct: 0 Critical, 5 High, 35 Medium, 36 Low; 70 Confirmed, 0 Latent, 5 Plausible, 1 Refuted |
| Invariants | 413 rows in 23 subject prefixes ([invariants.md](invariants.md)) |
| Rules for new code | 110 (`FR-01`…`FR-110`) in [rewrite-foundations.md](rewrite-foundations.md): 100 merged from 121 principle rules and 23 testing rules, 8 performance and reliability rules from the owner's goal, and 2 on features and packages from the owner's direction of 2026-10-20 |
| Size items over a threshold | 284, all reviewed in [size-review.md](size-review.md) (124 one concept, 160 split planned) |

## Where to start

- **Planning the cleanup:** [rewrite-foundations.md](rewrite-foundations.md): what must be fixed, what must be kept, the target module layout, the FR rules, the review checklist, the phased migration plan and the questions only the owner can answer.
- **Fixing something now:** [defects.md](defects.md), section "Fix before the cleanup starts", then [invariants.md](invariants.md) for the behaviour the fix must keep, and [testing.md](testing.md) for the regression test it needs.
- **Checking adherence:** [rule-status.md](rule-status.md) (rules against the current code), [status.md](status.md) (every finding's state), [progress.md](progress.md) (what landed), `python3 scripts/size-report.py`.
- **One principle:** the six documents in [principles/](principles/), each with systemic patterns, largest offenders, what to keep, the full finding index and its rules.
- **One area:** the area document below: file inventory, responsibility maps of the major types, findings, defects, what to keep and the area blueprint.

## Documents

| Document | What it holds |
| --- | --- |
| [rewrite-foundations.md](rewrite-foundations.md) | The design contract: fixes by cluster, keep list, target modules and import rules, composition root, ports, replacement types, state ownership, routing, feature template, concurrency and errors, the FR rules with the review checklist, the migration plan, owner questions |
| [invariants.md](invariants.md) | The acceptance specification: every behaviour and persisted format users depend on, one rule per row with enforcement and test idea; IDs are permanent |
| [defects.md](defects.md) | Every defect with verdict, calibrated severity, trace, minimal fix and preventing rule; the Phase 0 list |
| [testing.md](testing.md) | Verdict on the suite, coverage map, target test architecture, migration backlog, TR rules |
| [metrics.md](metrics.md) | Every measured number with its method |
| [findings-index.md](findings-index.md) | Every finding ID with area, severity and title (generated) |
| [size-review.md](size-review.md) | The size rule and the register `scripts/size-report.py` checks |
| [size-items.md](size-items.md) | The 285 items over a threshold at the snapshot (generated) |
| [rule-status.md](rule-status.md) | Each FR rule: Supported / Partial / Open / Not reassessed, with evidence |
| [status.md](status.md) | Every finding and defect with its current state (generated at the snapshot) |
| [progress.md](progress.md) | The cleanup log |
| [reviews/](reviews/) | Reviews of work that landed after the snapshot |

| Principle | Findings | High |
| --- | ---: | ---: |
| [Single responsibility](principles/single-responsibility.md) (`SRP`) | 75 | 13 |
| [Open closed](principles/open-closed.md) (`OCP`) | 52 | 3 |
| [Liskov substitution](principles/liskov-substitution.md) (`LSP`) | 58 | 8 |
| [Interface segregation](principles/interface-segregation.md) (`ISP`) | 40 | 3 |
| [Dependency inversion](principles/dependency-inversion.md) (`DIP`) | 52 | 4 |
| [Clean code](principles/clean-code.md) (`CC`) | 151 | 2 |

| Area | ID | Scope | Files | Code lines | S | O | L | I | D | CC |
| --- | --- | --- | ---: | ---: | --- | --- | --- | --- | --- | --- |
| [Shell](areas/shell.md) | `SHELL` | Workspace model, root view, sidebar, tabs, panes, commands, settings | 32 | 8,942 | Weak | Weak | Mixed | Weak | Weak | Mixed |
| [Editor](areas/editor.md) | `EDITOR` | Live Preview and source editor (TextKit 2), editing sessions | 19 | 8,062 | Weak | Mixed | Weak | Mixed | Mixed | Mixed |
| [Reading](areas/reading.md) | `READING` | Reading view, note pane, properties panel, file previews | 14 | 5,431 | Weak | Mixed | Weak | Mixed | Mixed | Mixed |
| [Mdcore](areas/mdcore.md) | `MDCORE` | Markdown model: parsing, blocks, editing commands, highlighting, HTML conversion | 18 | 6,895 | Mixed | Mixed | Weak | Mostly strong | Mostly strong | Mixed |
| [Vault](areas/vault.md) | `VAULT` | Storage, paths, settings, links, search query, GRDB index, file operations | 34 | 7,303 | Mixed | Mixed | Mostly strong | Mixed | Mixed | Mixed |
| [Bases](areas/bases.md) | `BASES` | Obsidian Bases: model, expressions, evaluator, index provider, views | 26 | 8,679 | Mixed | Weak | Weak | Mixed | Mixed | Mixed |
| [Canvas](areas/canvas.md) | `CANVAS` | JSON Canvas, graph view, maps | 20 | 4,751 | Mixed | Mixed | Mostly strong | Mixed | Mixed | Mixed |
| [Ink](areas/ink.md) | `INK` | Pencil drawings: file formats, editor, tools, selection, gestures | 33 | 8,118 | Mixed | Mixed | Mostly strong | Mixed | Weak | Mixed |
| [Lecture](areas/lecture.md) | `LECTURE` | PDF notebooks and annotations, lecture recording and video, diagnostics | 37 | 9,814 | Weak | Mixed | Mixed | Mixed | Mixed | Mixed |
| [Voice](areas/voice.md) | `VOICE` | Read Aloud: document model, system speech, neural voices, player | 53 | 8,116 | Weak | Mixed | Weak | Mixed | Mixed | Mixed |
| [Plugin](areas/plugin.md) | `PLUGIN` | Community plugins, Swift side: host, installer, bridge, themes | 27 | 4,968 | Weak | Weak | Mixed | Weak | Mixed | Mixed |
| [Runtime](areas/runtime.md) | `RUNTIME` | Community plugin JavaScript runtime (own code) | 14 | 7,287 | Weak | Mixed | Mixed | Mixed | Mixed | Mixed |
| [Architecture](cross-cutting/architecture.md) | `ARCH` | Module graph, composition root, state inventory, concurrency, navigation, errors, test architecture | — | — | Weak | Weak | Mixed | Weak | Weak | Mixed |

## Merged from the 2026-09-30 tracker

The earlier tracker `Docs/SOLID.md` (read it with `git show b13dec3:Docs/SOLID.md`) assessed a sample of boundaries and listed seven open work items. Every area audit re-checked its claims against the code (each area document's Summary says which hold). Each item is carried into this standard below, and where the earlier tracker allowed something this standard forbids, the stricter wording wins.

| Earlier item (2026-09-30) | Where it lives now | What is stricter now |
| --- | --- | --- |
| High: the conflict-version test store succeeds where production fails | `LSP-VAULT-02`; rules `FR-86` (one fake, production semantics), `FR-87` (one contract suite for every implementation) | The earlier fix was to align one fake; now every protocol with two implementations runs one shared contract suite, and fakes live only in a test-support target |
| High: workspace services and the shared Pencil, PDF and draft singletons are reached directly | `DIP-INK-01`, `DIP-SHELL-01`, the ARCH composition-root findings; `FR-46` (the app target is the only composition root), `FR-48` (no singleton, service locator or mutable static), `FR-42` | The earlier tracker held that "framework singletons are not automatically violations"; now a singleton or mutable static outside the platform edge (`FR-52`) is rejected in review |
| Medium: extract workflows from `WorkspaceModel` "as those areas change" | `SRP-SHELL-01`, `SRP-SHELL-02`, `SRP-ARCH-*`; `FR-01`, `FR-03`, `FR-04`; the replacement types in [rewrite-foundations.md](rewrite-foundations.md) section 6 | Extraction is a planned phase with an exit criterion, not opportunistic; more than about 15 stored properties needs a recorded reason |
| Medium: narrow the dependencies of navigation, discovery and session persistence | `ISP-SHELL-01` (74 views take the whole workspace), `ISP-ARCH-*`; `FR-02`, `FR-37`, `FR-38`, `FR-39` | No consumer takes the application root; capabilities have at most seven members; reading and destroying are separate capabilities |
| Medium: put Bases lookup failures inside the provider contract | `LSP-BASES-01`, `LSP-BASES-02`; `FR-59` (a failed read is never an empty result), `FR-87` | Applies to every reader, not only Bases: 624 `try?` sites must each state why the failure is harmless (`FR-58`) |
| Medium: consolidate document, template and format dispatch "when real extension work needs it", without a registry | `OCP-SHELL-01` (a new document kind touches 13 UI files), `OCP-ARCH-01`; `FR-17` to `FR-19` | Adding a kind is one enum case plus one descriptor now, not when the need arises; no `default:` over an own enum (`FR-18`) |
| Validation: exercise real camera capture and file-provider conflicts | [testing.md](testing.md) target architecture (device job), `FR-96` | Platform behaviour is tested where it runs, on a device in a nightly job (decision 8) |
| Principle: protocols only for a real substitution, test or isolation need | `FR-53` | Unchanged; it is the one place the earlier tracker and this standard agree word for word |
| Principle: "feature completeness and test counts alone do not establish SOLID compliance" | [rule-status.md](rule-status.md) | Rules are assessed against the code, never as a percentage of closed findings |

## Identifiers

- **Findings:** `<P>-<AREA>-<NN>`, with `P` ∈ {`SRP`, `OCP`, `LSP`, `ISP`, `DIP`, `CC`, `BUG`} and `AREA` one of the IDs above (for example `SRP-SHELL-01`, `BUG-CANVAS-01`). Defects found by the verifiers are `BUG-<AREA>-V<NN>`, by the lead `BUG-<AREA>-L<NN>`. IDs are never reused; a new finding takes the next free number.
- **Area invariants:** `<AREA>-INV-NN` in the area blueprints, merged into **[invariants.md](invariants.md) rows** with subject prefixes `B`, `C`, `D`, `ED`, `EX`, `G`, `INK`, `IX`, `LK`, `M`, `MD`, `N`, `NM`, `OB`, `P`, `PDF`, `PL`, `RA`, `REC`, `SEC`, `ST`, `TH`, `U` (for example `D-01`). Invariant IDs are permanent: never renumbered; a retired row is struck through.
- **Rules:** `FR-NN` in [rewrite-foundations.md](rewrite-foundations.md) section 11 (groups A–I); their sources are the owner's goal and the principle rules (`SRP n`, `OCP n`, `LSP n`, `ISP n`, `DIP n`, `CC n`) and testing rules (`TR n`).

## Severity

- **Structural findings:** **High** = wrong behaviour, data loss, a security or privacy problem, or something that blocks testing or change across the app. **Medium** = raises change cost or bug risk in one area. **Low** = readability or consistency.
- **Defects** (calibrated by reach in the shipped product): **Critical** = data loss, wrong destructive action, security or privacy, in normal use. **High** = wrong visible behaviour, hard to recover. **Medium** = recoverable, or serious only on a fallback path. **Low** = cosmetic, rare, latent, debug or test only. Verdicts: Confirmed, Latent, Plausible, Refuted ([defects.md](defects.md)).

## How the audit was done

1. **Frozen snapshot.** The audit read commit b13dec3 only, exported with `git archive b13dec3`, never the working tree (other sessions edit it). Uncommitted work is out of scope. No source code and no git state changed.
2. **Reconnaissance.** Sizes, pattern counts, change hotspots, comment statistics and the import graph were measured by script before any reading ([metrics.md](metrics.md); reproducible with `scripts/solid-metrics.py` and `scripts/size-report.py --list`). The code was split into twelve areas of 4,751–9,814 code lines plus one cross-cutting architecture area.
3. **Parallel auditors with one brief.** Thirteen auditors (Claude Opus 5.5 at high effort, run through the Anthropic API with read-only tools over the snapshot) each read every line of one area and wrote one area document in the same nine-part structure, checking the earlier `Docs/SOLID.md`, `Architecture.md` and `Coverage.md` claims first.
4. **Double-checked defects.** Four independent verifiers (Opus 5.5) re-traced every reported defect from trigger to outcome without trusting the report, calibrated its severity by reach and found four more. The lead re-read the code of every High defect, the refuted one and the keychain one a third time, and found one more ([defects.md](defects.md), "Third reading by the lead").
5. **Synthesis from the area documents.** The principle documents, invariants, testing, size register and design contract were written from the area documents (never from memory), with every High finding re-checked against the code. The API credit ran out during synthesis; the remaining synthesis documents were written by Claude Code subagents (Sonnet) from the same inputs.
6. **Mechanical checks.** Every one of the about 12,648 relative links was checked by script to resolve to an existing file and an in-range line; the lead compared 30 randomly chosen line citations with the source, and the invariants writer 80 more.

## Limits

- **Static reading only.** No test, build, simulator or device run was part of the audit. Defects marked Plausible need a runtime check, named in each entry. Performance statements cite the code's own measurements or comments, not new measurements.
- **Counts depend on method.** Code lines exclude comments, blank lines and string contents; pattern counts are regex occurrences in code with comments and strings removed. Area documents measured with an earlier counter differ from [metrics.md](metrics.md) by a few lines per module.
- **Line numbers are frozen to b13dec3.** Read any cited line with `git show b13dec3:<path>` (for example `git show b13dec3:Sources/GraphiteUI/WorkspaceModel.swift | sed -n 300,340p`); links into the working tree drift as the code changes.
- **Vendored code is out of scope:** `Vendor/textual`, `Vendor/swiftui-math`, `Vendor/mlx-audio-swift` and the minified bundles under `Resources/CommunityPluginRuntime/Vendor/`.
- **The design contract is binding** since the owner answered its questions on 2026-10-18 (section 13 of [rewrite-foundations.md](rewrite-foundations.md)); no cleanup wave starts before the owner says go.
