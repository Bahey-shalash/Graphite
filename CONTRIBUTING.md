# Contributing to Graphite

Thank you for helping. Graphite is a small team's project with a strict standard, so a few things keep contributions easy to accept.

## Before you start

- Read [OBJECTIVE.md](OBJECTIVE.md). Graphite's promise is that the user's files stay ordinary files: Markdown, PDF, PNG, SVG, M4A and MP4 that other apps can read. A change that invents a Graphite-only format or a sidecar file cannot be merged.
- Read [RULES.md](RULES.md) and the binding standard in [Docs/solid/](Docs/solid/README.md): rules `FR-01` onward, the invariants a change must keep, and the review checklist in `Docs/solid/rewrite-foundations.md` section 11. Names are full and descriptive, without invented abbreviations.
- For anything larger than a bug fix, open an issue first so the approach can be agreed before you write it.

## Making a change

1. Fork the repository and create a branch with a descriptive name, such as `fix-pdf-page-rotation`.
2. Keep the change focused on one thing, with tests that fail without it.
3. Run the checks locally:

   ```bash
   swift test --parallel
   python3 scripts/size-report.py
   ```

4. Update [Docs/Architecture.md](Docs/Architecture.md) and [Docs/Coverage.md](Docs/Coverage.md) when behaviour or structure changes. Do not describe incomplete or untested behaviour as finished.
5. Open a pull request and fill in the template.

## Keep the core small

Graphite's size, memory use and battery cost are part of the product. New pictures, fonts, voices or models are downloaded on first use rather than bundled into the app, and a feature that can be switched off must cost nothing while it is off.

## License

By contributing, you agree that your contribution is licensed under the [Apache License 2.0](LICENSE).
