# Siri answers from the vault: TODO

Created: 2026-10-19.

Status: not started. Graphite has no App Intents, App Entities or Core Spotlight code yet, and no use of the Foundation Models framework.

## Request

The user asks Siri an ordinary question, with Graphite closed and without naming the app: "what did we learn in class today", "what did the professor say about Tomasulo's algorithm", "how does this work", "find me the note about caches". When the vault holds the answer, Siri answers from the notes and links to the note in Graphite. When it does not, Siri answers the way it normally would. It is an optional core feature; a bigger vault should mean better answers. Apple Private Cloud Compute is acceptable.

## How Apple supports it (iOS, iPadOS and macOS 27)

- Apple's announcement of Siri AI: "personal context understanding extends to third-party apps when developers integrate with Spotlight". Siri falls back to world knowledge and the web on its own, and runs on Apple Foundation Models on device and on Private Cloud Compute.
- The App Intents Notes schema domain: `@AppEntity(schema: .notes.note)` has `name`, `content: AttributedString?`, `attachments`, `isPinned`, `creationDate`, `modificationDate` and `folder`. The intents are `createNote`, `updateNote` and `appendText`. Available from iOS, iPadOS and macOS 27; used by Siri and Shortcuts.
- Entities submitted to the Spotlight semantic index are how Siri finds the right note when the question is asked. Apple does the retrieval and writes the answer; Graphite describes each note and keeps the index current.
- Outside Graphite's control: Siri AI needs an iPhone 16 or later, some Pro models, or an M-series iPad or Mac. It launches in English first and not in the EU at first on iOS and iPadOS (Switzerland is not in the EU; check on the devices). How good the answers are, and when Siri prefers notes over the web, is Apple's decision.

Sources: [Apple newsroom, Siri AI](https://www.apple.com/newsroom/2026/06/apple-introduces-siri-ai-a-profoundly-more-capable-and-personal-assistant/), [App schema domains](https://developer.apple.com/documentation/appintents/app-schema-domains), [`note` entity schema](https://developer.apple.com/documentation/appintents/appschema/notesentity/note), [Making actions and content discoverable by Apple Intelligence](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence), [WWDC26 session 240](https://developer.apple.com/videos/play/wwdc2026/240/), [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/).

## Scope

- [ ] Device check first (one to two days): a minimal `NoteEntity` with the `.notes.note` schema and `IndexedEntity`, about 50 notes of a test vault indexed. Kill Graphite, ask Siri the questions above on the iPad and an iPhone with Siri AI on. Record whether Siri uses note bodies and not only titles, whether the answer links to the note, how long a note can be before it is cut, and how fast an edit reaches the answers. If Siri ignores third-party note content, build the fallback below instead.
- [ ] `NoteEntity` (`.notes.note` plus `IndexedEntity`): identifier is the vault-relative path, name is the title, content is the Markdown body as plain text (front matter removed, wikilinks reduced to their visible text), dates from the file, folder from a `FolderEntity` with the `.notes.folder` schema.
- [ ] `NoteEntityQuery` resolves identifiers, strings and suggestions through `VaultIndex`, so it works when Siri launches Graphite in the background.
- [ ] Long lecture notes: if the device check shows long content is cut, also index heading-level section entities so an answer lands on `[[Note#Heading]]`.
- [ ] Keep Spotlight current from the existing index paths: `VaultIndex.reconcile(root:)` sends only changed notes and removes deleted ones; `refresh(paths:root:)` and `VaultMonitor` push single-note changes with the IX-08 debounce; renames delete the old identifier; batches at `.utility` priority (IX-07). A background refresh task picks up notes edited on the Mac and synced by iCloud while Graphite was closed.
- [ ] `OpenNoteIntent` (`OpenIntent`, with an open schema from the System and in-app search domain if one fits) opens the note through the existing `graphite://` routing, so Siri's answer carries a tappable link into Graphite.
- [ ] Optional, cheap once the entity exists: `createNote`, `appendText` and `updateNote` schema intents ("add this to my lecture 7 note").
- [ ] Core plugin "Siri and Spotlight" in `GraphitePreferences.CorePlugin`, off by default because note text is copied into the system index. Turning it off deletes every item Graphite indexed. A list of excluded folders (private journals). A line in its settings page saying why it is unavailable when Siri AI is missing. Guarded by `#available(iOS 27, *)`; the iOS deployment target stays 18.
- [ ] Tests: Markdown to entity content (front matter, wikilinks, callouts); only changed notes are sent; rename and delete remove old identifiers; nothing is indexed while the plugin is off; excluded folders are skipped; a hosted test that `NoteEntityQuery` resolves paths through `VaultIndex`.
- [ ] On the iPad, then an iPhone: Graphite killed, Siri answers the questions above from the notes with a link; a question the vault does not cover gets normal Siri; an edit made on the Mac shows up after the next index pass.
- [ ] `Architecture.md`, `Coverage.md` and `Docs/solid/invariants.md` updated once built and tested; `python3 scripts/size-report.py` passes.

## Fallback or addition: Graphite's own answers ("Ask Graphite …")

Only reachable when the user names the app, so it is the fallback if Siri ignores note bodies, or an addition for answers that quote sources closely.

- [ ] A passages table in `VaultIndex` (heading-sized chunks, BM25), later merged with on-device `NLContextualEmbedding` vectors (multilingual, so French and English notes match).
- [ ] An answerer on a Foundation Models `LanguageModelSession`: on device the context is 4,096 tokens shared by prompt and answer, so only the best passages (about 2,500 tokens) go in, with citations; Private Cloud Compute (32K tokens) when the user opts in.
- [ ] `AskVaultIntent` with an "Ask Graphite …" phrase, returning a spoken answer and a snippet of the source notes.
- [ ] Check first whether the on-device model may run when Siri launches Graphite in the background (Apple rate-limits background use).

## Storage rules

- Spotlight and any passages or embeddings are disposable copies outside the vault (IX-01); losing them costs only search, never content.
- Nothing is sent to the system index while the plugin is off, and excluded folders never are.
- Nothing leaves the device unless the user turned on Private Cloud Compute (Siri's own use of Private Cloud Compute is Apple's setting).

## Open questions

- Does Siri AI reach third-party note bodies in practice, and in which countries and languages on the owner's devices?
- Index whole notes, sections, or both?
- Should PDFs (with the existing Vision text recognition) and drawings' recognized text be indexed too?
