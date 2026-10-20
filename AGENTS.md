# Graphite repository instructions

Read `OBJECTIVE.md` and `RULES.md` before editing this repository. Follow both throughout implementation and review.

`OBJECTIVE.md` defines the intended product and ordinary-file storage contracts. `RULES.md` defines coding guidelines, including mandatory full, descriptive names and no invented abbreviations.

Keep `Docs/Architecture.md` and implementation coverage documentation aligned with actual code. Do not claim incomplete or untested behavior is complete.

`Docs/solid/` is the binding code-quality standard. The goal is the fastest and most resource-efficient app Graphite can be: robust, free of defects, fast, fluid and reliable. Every change must follow the rules `FR-01` to `FR-108` and answer the review checklist in `Docs/solid/rewrite-foundations.md` section 11, keep the invariants in `Docs/solid/invariants.md` (name the ones it touches), and pass `python3 scripts/size-report.py`. Where the standard and older text disagree, the stricter rule wins. Cleanup waves follow the phased plan in section 12 and update `Docs/solid/progress.md`, `status.md` and `rule-status.md` with evidence from the current code.
