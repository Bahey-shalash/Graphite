# Reviews

Snapshot: b13dec3 (main, 2026-10-18).

Reviews of work that landed outside the audited snapshot: a commit or branch made after b13dec3 that the audit did not read. Each review is one file named `<YYYY-MM-DD>-<branch-or-topic>.md` and says:

- the commits reviewed (`git log --oneline <base>..<head>`);
- which findings it fixes, worsens or adds (new IDs continue the area's numbering: the next `SRP-EDITOR` number after the last one in [findings-index.md](../findings-index.md));
- which invariants ([invariants.md](../invariants.md)) it touches and whether tests pin them;
- the answers to the review checklist in [rewrite-foundations.md](../rewrite-foundations.md), section 11.

No reviews yet. Landed after the snapshot and not yet reviewed: `3f7c726` (restructures `Graphite.xcodeproj/project.pbxproj` into synchronized folders; the architecture audit's statements about the app and test targets' file lists describe b13dec3).
