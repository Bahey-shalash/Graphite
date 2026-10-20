# Graphite

Graphite is a native Apple Pencil-first knowledge and study app for ordinary Obsidian-compatible folders. Markdown, PDFs, images, and recordings remain usable outside the app. [OBJECTIVE.md](OBJECTIVE.md) defines the product and storage contracts. [RULES.md](RULES.md) defines the engineering standard.

## Engineering standard

The goal is the fastest and most resource-efficient app Graphite can be: robust, free of defects, fast, fluid and reliable. [Docs/solid/](Docs/solid/README.md) is the binding standard for that goal: an audit of every line at commit `b13dec3` (2026-10-18) with its findings, the 76 verified defects, the 413 invariants a change must keep, and the rules all new code is held to (`FR-01` onward, with a review checklist), plus the phased plan that brings the existing code there. [RULES.md](RULES.md) and [OBJECTIVE.md](OBJECTIVE.md) stay authoritative over it.

The audit found the Core value types, file formats and storage contracts sound, and the coordinating layer weak: one workspace object holds 86 stored properties, there is no composition root, and several rules are implemented more than once and already disagree. [Docs/solid/rule-status.md](Docs/solid/rule-status.md) states which rules the code meets today, [Docs/solid/status.md](Docs/solid/status.md) the state of every finding, and [Docs/solid/progress.md](Docs/solid/progress.md) what each cleanup wave changed. `python3 scripts/size-report.py` checks function, type and file sizes against the review register.

## Evidence and implementation status

The 2026-10-18 audit read source and tests at `b13dec3` without running builds, tests, the simulator or a device; its limits are listed in [Docs/solid/README.md](Docs/solid/README.md#limits). It makes no numerical compliance claim.

- [Architecture](Docs/Architecture.md): module direction, ownership, storage, and technical risks.
- [Implementation coverage](Docs/Coverage.md): implemented behavior, dated validation, and incomplete or unverified work.
- [SOLID and clean-code standard](Docs/solid/README.md): findings, defects, invariants, rules for new code, and the cleanup plan.
- [Community plugins](Docs/Community-plugins.md): how Graphite runs Obsidian community plugins, what works, what does not yet, and how it was checked.
- [Releasing to TestFlight](Docs/TestFlight.md): the App Store Connect record, uploading a build, and what the upload declares.

After each cleanup wave, update [Docs/solid/progress.md](Docs/solid/progress.md), [status.md](Docs/solid/status.md) and [rule-status.md](Docs/solid/rule-status.md) from the current code. Feature completeness and test counts alone do not establish SOLID compliance.
