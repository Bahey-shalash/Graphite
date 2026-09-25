# Graphite engineering rules

These rules apply to all Graphite implementation, tests, scripts, and reviews. Read `OBJECTIVE.md` before changing product behavior or storage decisions. The product objective remains authoritative.

## Explicit, descriptive names are mandatory

Use complete words that explain the responsibility, meaning, and units where relevant. Do not invent abbreviations or shorten names to save typing. A reader should understand a name without reconstructing missing letters or consulting a glossary.

- Use `document`, not `doc`.
- Use `directory`, not `dir`.
- Use `configuration`, not `config`.
- Use `context`, not `ctx`.
- Use `manager`, not `mgr`.
- Use `controller`, not `ctrl`.
- Use `temporaryFileURL`, not `tmp` or `tempURL`.
- Use `fileExtension`, not `ext`.
- Use `sourceText`, not `src`.
- Use `destination`, not `dest` or `dst`.
- Use `database`, not `db`.
- Use `fileSystem`, not `fs`.
- Use `regularExpression`, not `regex` or `re`.
- Use `error`, not `err` or `e`.
- Use `index`, `pageIndex`, or `chunkIndex`, not `i`, `j`, or `idx`.
- Use `point`, `width`, and `height`, not `p`, `w`, and `h`.
- Use `leftPath` and `rightPath`, not `lhs` and `rhs`.
- Use `elapsedSeconds` or `maximumPayloadBytes` when units matter.

The rule applies to types, properties, local variables, parameters, functions, files, tests, and scripts. Prefer explicit closure parameter names when the meaning of anonymous positional parameters is not immediately obvious. Do not use a misleadingly generic name such as `data`, `value`, `item`, or `result` when a precise domain name would clarify the code.

Established platform API and file-format names remain unchanged: `URL`, `UUID`, `PDF`, `PNG`, `JSON`, `YAML`, `UTF8`, `PDFKit`, `PencilKit`, `PKDrawing`, `NSFileCoordinator`, and required framework protocol members. These exceptions do not justify invented abbreviations in Graphite-owned names. Standard mathematical coordinate members such as `CGPoint.x` are framework API, not permission to name unrelated variables with single letters.

Use Swift's normal UpperCamelCase type names and lowerCamelCase member names. Functions should state the operation. Boolean names should read as facts or questions, such as `isDirectory`, `hasUnsavedChanges`, and `canResumeRecording`. Avoid redundant type suffixes and speculative names such as `UniversalManager` or `EverythingService`.

## Apply SOLID without unnecessary machinery

- Single responsibility: a component has a coherent responsibility and reason to change. Editors do not implement filesystem policy or database migrations.
- Open/closed: add document handlers, page templates, and adapters through focused boundaries. Do not scatter extension checks throughout the application.
- Liskov substitution: implementations must honor the same safety, error, and lifecycle contracts. A test adapter must not make an operation appear safer than production.
- Interface segregation: expose the smallest useful capability. Read-only navigation does not require an unrestricted write interface.
- Dependency inversion: product logic depends on relevant capabilities and value types, not global mutable singletons or a particular view. Inject dependencies at composition boundaries.

Use protocols when there is a real substitution, test, or isolation need. Do not add one protocol per class, speculative factories, or layers that only forward calls. Prefer simple value types and clear ownership.

## Native frameworks and open-source reuse

Use Swift and SwiftUI with UIKit/AppKit bridges where mature native controls are the correct solution. Reuse PencilKit, PDFKit, AVFoundation, TextKit, Foundation document APIs, ImageIO, and standard undo infrastructure.

Before implementing major infrastructure, inspect Apple's APIs and mature permissively licensed libraries. Reuse a Markdown parser rather than writing one. Record dependency purpose, license, version, maintenance status, and storage implications. Pin reproducible builds and preserve required license notices. A dependency must never override Graphite's storage contracts.

## Ordinary files first

Markdown, PDFs, PNG images, and normal media files are authoritative. Never introduce proprietary document extensions, required visible sidecars, or an authoritative application database. Optional embedded editing metadata must degrade safely to complete visible standard content.

Preserve existing Markdown syntax, frontmatter, line endings, paths, and attachments unless an intentional edit changes them. Indexing and preview must not rewrite source files. Resolve attachment destinations through the Obsidian settings policy. Do not reorganize the user's vault for implementation convenience.

## Concurrency, ownership, and performance

Keep UI work on the main actor. Give background services explicit ownership of mutable state. Do not cross actors with live mutable framework objects unless their documented thread-safety and ownership make it safe. Explain any `@unchecked Sendable` conformance with a concrete invariant.

Keep vault scans, content parsing, indexing, image encoding, PDF writes, and recording finalization off the main thread. Use cancellation, bounded concurrency, backpressure, and cache budgets. A scan cannot create an unbounded task for every file. Document opening must not depend on indexing completing.

Do not load every note, attachment, thumbnail, or PDF page. Search and navigation operate on bounded results. Avoid whole-vault observation updates during typing. Measure cold and warm behavior, memory, and sustained interaction. Never claim 100,000-file readiness from architectural intent alone.

## File integrity and error handling

Use security-scoped access for selected folders. Validate vault boundaries, relative paths, and symbolic links. Coordinate external-provider operations. Stage writes safely, detect changed revisions, and replace atomically where supported.

Do not silently overwrite external edits, delete conflict versions, ignore failed saves, or report a successful operation before it succeeds. A failed save retains recoverable work. Distinguish user content from disposable caches.

Do not use `try!` or force unwraps in file-handling code. Prefer explicit throwing errors and meaningful recovery. Use `try?` only when failure is intentionally optional, such as best-effort cleanup; explain non-obvious cases. Bound untrusted metadata sizes and allocations before decoding.

## Test observable behavior

Use unit tests for non-UI policies and integration tests at framework/storage boundaries. Important coverage includes attachment strategies, Unicode and spaces, Wikilinks, source preservation, conflicts, PNG fallback and Pencil round trips, PDF validity and annotation visibility, page operations, coordinate transforms, and recording transitions/output.

Test with independent image/PDF/media readers where feasible. Include corrupt metadata, missing files, external changes, canceled scans, large inputs, and failed writes. Do not substitute tests that merely mirror implementation for interoperability evidence.

Build frequently, run checks appropriate to the change, and fix failures before adding more layers. Record which checks ran and which require a physical device. Do not label untested behavior as verified.

## Code clarity and delivery

Keep functions focused, reduce nesting with guard clauses, use typed state instead of loosely related booleans, and eliminate unexplained constants. Comments explain an invariant, tradeoff, or platform constraint rather than restating obvious code.

Keep public APIs small. Avoid global mutable state, broad catch-and-ignore blocks, hidden side effects, and unrelated refactors. Keep user-facing copy free of implementation jargon.

Every visible control must perform a real action or accurately communicate why it is unavailable. Do not ship fake data as real user content, inert buttons, TODO-only features, or placeholder success paths. Document incomplete capabilities separately from completed behavior.

When a platform constraint prevents a requested behavior, document the limitation, the standards-compatible alternative, its interoperability effect, and the remaining validation. Do not silently change the product objective to make implementation easier.
