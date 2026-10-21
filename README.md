<p align="center">
  <img src=".github/assets/graphite-icon.png" width="128" height="128" alt="Graphite app icon">
</p>

<h1 align="center">Graphite</h1>

<p align="center">
  <strong>An Apple Pencil-first study app for your Obsidian vault.</strong><br>
  Notes, handwriting, PDFs and lecture recordings, kept as ordinary files you own.
</p>

<p align="center">
  <img alt="Platforms: iPadOS, iOS, macOS" src="https://img.shields.io/badge/platforms-iPadOS%20%7C%20iOS%20%7C%20macOS-lightgrey">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="Status: TestFlight beta" src="https://img.shields.io/badge/status-TestFlight%20beta-blue">
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/license-Apache%202.0-green"></a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="AddOns/WelcomeTour/WelcomeTourDrawingInNote-dark.jpg">
    <img src="AddOns/WelcomeTour/WelcomeTourDrawingInNote-light.jpg" width="820" alt="Graphite on iPad: a Markdown note with an Apple Pencil drawing and a table of formulas">
  </picture>
</p>

Graphite gives an Obsidian vault the notebook and PDF tools of Goodnotes without locking anything away. It opens an ordinary folder and edits it in place: notes stay Markdown, notebooks and slides stay PDF, drawings stay PNG, PDF or SVG, and recordings stay M4A. If Graphite disappeared tomorrow, Obsidian, Finder, Preview and any Markdown editor could still read every file.

It is a native app written in Swift, built iPad-first for lectures and handwriting, with a Mac app that stays small and fast and an iPhone app that works as a quick Obsidian client.

## Features

- **Markdown, the Obsidian way.** Live Preview, reading view and source mode; Wikilinks, embeds, callouts, math, tables, tasks, tags, properties and frontmatter, without rewriting notes on open.
- **Pencil drawings inside notes.** Draw on a full-width canvas and Graphite saves an ordinary image in your attachment folder with a normal `![[embed]]`, re-editable later.
- **PDF notebooks.** One system for blank notebooks, lecture slides, worksheets and scans: paper templates, page thumbnails, reordering, bookmarks, and annotations stored in the PDF itself.
- **Lecture recording** that keeps going while you move between documents.
- **Knowledge tools.** Full-text search, backlinks, outgoing and unresolved links, outline, tags, Bases (table, cards, list and map views), each switchable like Obsidian's core plugins.
- **Obsidian community plugins and themes**, run from the vault's own `.obsidian` folder. See [what works today](Docs/Community-plugins.md).
- **Import from Goodnotes and Notability** into ordinary PDFs and recordings.
- **A small core.** Extras such as voices and tour pictures are downloaded on first use, so the app stays light in size, memory and battery.

<table>
  <tr>
    <td><img src="AddOns/WelcomeTour/WelcomeTourEmbeddedPDF-light.jpg" alt="A lecture slide embedded in a Markdown note on iPad"></td>
    <td><img src="AddOns/WelcomeTour/WelcomeTourNote-mac-light.jpg" alt="A note with math and a callout in the Mac app"></td>
  </tr>
  <tr>
    <td align="center"><sub>A slide embedded in a note, on iPad</sub></td>
    <td align="center"><sub>The native Mac app</sub></td>
  </tr>
</table>

## Status

Graphite is in beta on TestFlight as **Graphite Note**, for iPad, iPhone and Mac. It is under active development: what has been built and how it was checked is recorded in [Implementation coverage](Docs/Coverage.md), and incomplete work is listed there too.

## Building

Requirements: Xcode 27 and the iOS 27 and macOS 27 SDKs.

1. Open `Graphite.xcodeproj` and run the **Graphite** scheme on an iPad, an iPhone, a simulator or My Mac. Set your own development team under Signing & Capabilities.
2. Run the package tests from the command line:

```bash
swift test --parallel
```

The checks continuous integration runs are described at the top of [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first: [OBJECTIVE.md](OBJECTIVE.md) defines what Graphite is and the file formats it must keep, and [RULES.md](RULES.md) with [Docs/solid/](Docs/solid/README.md) define how code is written. To report a vulnerability, see [SECURITY.md](SECURITY.md).

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

## License

Graphite is licensed under the [Apache License 2.0](LICENSE). Code under `Vendor/` keeps its own license, stated in each folder. See [NOTICE](NOTICE).
