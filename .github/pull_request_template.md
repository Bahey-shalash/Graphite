## What this changes

<!-- One or two sentences, and the issue it closes if there is one. -->

## How it was checked

<!-- Tests added or run, devices and simulators used. -->

## Checklist

- [ ] Files stay ordinary files: no new format or sidecar ([OBJECTIVE.md](../OBJECTIVE.md))
- [ ] Follows [RULES.md](../RULES.md) and the review checklist in `Docs/solid/rewrite-foundations.md` section 11; invariants touched are named below
- [ ] `swift test --parallel` and `python3 scripts/size-report.py` pass
- [ ] `Docs/Architecture.md` and `Docs/Coverage.md` updated where behaviour changed
- [ ] Nothing new bundled into the app that could be downloaded on first use

Invariants touched:
