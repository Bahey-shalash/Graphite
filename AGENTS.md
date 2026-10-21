# Graphite repository instructions

Read `OBJECTIVE.md` and `RULES.md` before editing this repository. Follow both throughout implementation and review.

`OBJECTIVE.md` defines the intended product and ordinary-file storage contracts. `RULES.md` defines coding guidelines, including mandatory full, descriptive names and no invented abbreviations.

Keep `Docs/Architecture.md` and implementation coverage documentation aligned with actual code. Do not claim incomplete or untested behavior is complete.

`Docs/solid/` is the binding code-quality standard. The goal is the fastest and most resource-efficient app Graphite can be: robust, free of defects, fast, fluid and reliable. Every change must follow the rules `FR-01` to `FR-110` and answer the review checklist in `Docs/solid/rewrite-foundations.md` section 11, keep the invariants in `Docs/solid/invariants.md` (name the ones it touches), and pass `python3 scripts/size-report.py`. Where the standard and older text disagree, the stricter rule wins. Cleanup waves follow the phased plan in section 12 and update `Docs/solid/progress.md`, `status.md` and `rule-status.md` with evidence from the current code.

## Todos: a Markdown file and GitHub issues

Every piece of planned work has two records, kept in step in the same commit:

- The Markdown file `Docs/<Feature>-todo.md` is the record: request, scope as `- [ ]` items grouped in numbered sections, decisions. It says what is done and how it was checked.
- One GitHub issue in `Graphite-Note/Graphite` per section of that file (one "<Feature>: the whole scope" issue when the file has no sections). The issue points at the file; it never holds the detail itself.

Writing a todo (a new file, a new section or a new item):

1. Write it in the Markdown file first.
2. Open the issue with `gh issue create --repo Graphite-Note/Graphite`, title `<Feature>: <section heading>`, and the feature's label (create it if missing: `gh label create <feature> --description "<Feature> (Docs/<Feature>-todo.md)"`), plus `verification`, `ipad` or `mac` where they apply. Body:
   - `Tracks the section [N. Heading](https://github.com/Graphite-Note/Graphite/blob/main/Docs/<Feature>-todo.md#anchor) of Docs/<Feature>-todo.md: k of its n items were open when this issue was opened.`
   - `That file is the record: tick the items there. The commit that ticks the section's last item closes this issue (Closes and this issue's number).`
   - The open items, one line each.
3. A new item in a section that already has an issue goes on that issue as a comment; it does not get a second issue.

Finishing a todo:

1. Tick it in the Markdown file: `- [x]` and `Done <YYYY-MM-DD>:` what was built, which tests cover it, what was checked on a device. Untested or unchecked work stays `- [ ]`.
2. The commit that ticks the last open item of a section ends its message with `Closes #N`, so pushing it to `main` closes the issue. Ticking an earlier item leaves the issue open.
3. An item dropped instead of built is struck through in the file with the reason; a section dropped as a whole closes its issue with `gh issue close N --reason "not planned" --comment "<reason>"`.
