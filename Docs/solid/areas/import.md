# Import: Goodnotes and Notability readers

Snapshot: written at `5aae924` (main, 2026-10-20). The area did not exist at `b13dec3`; commits `2118a0d` ("GraphiteCore reads Goodnotes notebooks page by page") and `ef17091` ("GraphiteCore reads Notability notes") added it.

## 1. Summary

`Sources/GraphiteCore/NotebookImport/` holds 49 files (about 4,000 code lines): a container and binary-format layer (ZIP with deflate, Apple LZ4, protocol buffers, Goodnotes `tpl` images, binary and XML property lists, `NSKeyedArchiver` archives, packed little-endian arrays) and two readers that decode a `.goodnotes` notebook and a Notability `.note` into page-by-page values with typed issues. The readers take bytes and return `Sendable` values; they do no file I/O and are not wired into the app yet (`git grep` finds no caller outside the folder and `Tests/`), so every finding here is latent until the import converter (the import plan's Phase 3) uses them. The formats are described in `Docs/Goodnotes-format.md` and `Docs/Notability-format.md`.

The layer is careful with hostile input: every length, count, offset and index is checked before use, the checks are written as subtractions and divisions so they cannot overflow, there is no `try!`, `as!`, force unwrap or `fatalError`, and seeded fuzz tests truncate and mutate every format. The findings are about memory bounds that are too generous for an iPad, guards each caller must remember, failed reads that come back empty, and helpers written twice.

| Measure | Value |
| --- | --- |
| Files | 49 (17 container and format, 32 reader) |
| Findings | 19: 2 defects (1 Medium, 1 Low) and 17 structural (7 Medium, 10 Low) |
| Wired into the app | No |
| Tests | Malformed-input and fuzz tests for every format; real-notebook tests run only on the owner's Mac (`CC-IMPORT-12`) |

## 2. Findings: container and format layer

Audited at `5aae924`; links are relative to this document.

#### CC-IMPORT-01 A ZIP entry commits its declared size (up to 512 MiB) before one byte is inflated, with no bound on the compression ratio
- **Severity:** Medium
- **Rule:** `FR-105`, `FR-78`
- **Evidence:** `contents(of:)` compares the declared `uncompressedByteCount` only with `maximumEntryBytes` ([ZipArchive.swift:81-83](../../../Sources/GraphiteCore/NotebookImport/ZipArchive.swift#L81-L83)); `inflate` then allocates `[UInt8](repeating: 0, count: max(expectedByteCount, 1))` ([:184](../../../Sources/GraphiteCore/NotebookImport/ZipArchive.swift#L184)); the limit is 512 MiB, "the bounds of the reference readers in `scripts/`" ([NotebookImportLimits.swift:24-28](../../../Sources/GraphiteCore/NotebookImport/NotebookImportLimits.swift#L24-L28)), and nothing compares the declared size with `compressedByteCount`. Introduced in `2118a0d`.
- **Why it matters:** a 200-byte entry that declares 500 MiB makes the reader commit 500 MiB of zeroed pages before failing at the first deflate byte: near an iPhone app's memory limit and far over an extension's, so the person sees a crash instead of a typed error. Deflate cannot expand more than about 1032:1, so such an entry is provably damaged before any allocation.
- **Fix direction:** refuse an entry whose declared size exceeds its compressed size times 1032 plus a small slack, before allocating; choose `maximumEntryBytes` per platform in `NotebookImportLimits`.

#### CC-IMPORT-02 Expanding a plain property list is budgeted at one value per byte, an unnamed budget that allows about 20 GiB
- **Severity:** Medium
- **Rule:** `FR-78`, `FR-105`
- **Evidence:** `valueBudget: byteCount` ([PropertyListValue.swift:57-62](../../../Sources/GraphiteCore/NotebookImport/PropertyListValue.swift#L57-L62)); `PropertyListValue` is an `indirect enum`, so every value is a heap box of at least 32 bytes ([:4](../../../Sources/GraphiteCore/NotebookImport/PropertyListValue.swift#L4)); `NotebookImportLimits` has no value-count field. Introduced in `ef17091`.
- **Why it matters:** a property list with shared members in a 512 MiB entry expands to 512 million values (about 20 GiB) before `valueCountOverBudget` is thrown; the cycle and depth checks do not bound this.
- **Fix direction:** a named `maximumPlainValueCount` in `NotebookImportLimits`, sized to the largest real shapes and recordings lists, passed through `plainValue(ofObjectAt:maximumNestingDepth:)`.

#### CC-IMPORT-03 Fixed-width reads of packed arrays depend on every caller's length check, and are unchecked memory reads in release builds
- **Severity:** Medium
- **Rule:** `FR-68`, `FR-71`
- **Evidence:** `PackedLittleEndianValues` reads "at entry indices the caller has checked" ([PackedLittleEndianValues.swift:3-4](../../../Sources/GraphiteCore/NotebookImport/PackedLittleEndianValues.swift#L3-L4)) with `loadUnaligned(fromByteOffset:)` ([:13-15](../../../Sources/GraphiteCore/NotebookImport/PackedLittleEndianValues.swift#L13-L15)), whose bounds are checked only in debug builds; `byte(at:)` and `uuid(at:)` trap instead, so out-of-range behaviour differs within one type; the type stores no size or count, and the only checks are at the callers ([NotabilityInk.swift:147-150](../../../Sources/GraphiteCore/NotebookImport/NotabilityInk.swift#L147-L150)). `LittleEndianBytes` in `ZipArchive.swift` has the same pattern. Introduced in `ef17091` and `2118a0d`.
- **Why it matters:** today's callers check exact byte counts, so nothing reads out of bounds; the first new packed array that misses the caller-side check becomes a heap over-read on hostile input.
- **Fix direction:** an entry size and count validated once in a throwing initializer (the check now in `NotabilityInk.packedValues`); reads through a bounds-checked accessor.

#### CC-IMPORT-04 The XML nesting pre-scan does not hold the guarantee its comment states
- **Severity:** Low
- **Rule:** `FR-80`, `FR-68`
- **Evidence:** the comments say a list that nests too deep "is refused before it is parsed" ([PropertyListDocument.swift:13-16](../../../Sources/GraphiteCore/NotebookImport/PropertyListDocument.swift#L13-L16), [:46-47](../../../Sources/GraphiteCore/NotebookImport/PropertyListDocument.swift#L46-L47)); the scan counts only the exact tag texts `array` and `dict` ([:48-62](../../../Sources/GraphiteCore/NotebookImport/PropertyListDocument.swift#L48-L62)), while Foundation also parses `<array >`, `<array x="1">` and tags split by a newline, and the scan counts tags inside comments. The real bound is Foundation's own nesting limit plus the depth checks after parsing ([:70](../../../Sources/GraphiteCore/NotebookImport/PropertyListDocument.swift#L70), [:80](../../../Sources/GraphiteCore/NotebookImport/PropertyListDocument.swift#L80)). Introduced in `ef17091`.
- **Why it matters:** the safety argument rests on a check that can be bypassed, and a valid file with tags in a comment can be refused.
- **Fix direction:** drop the scan and document the real bound, or end tag names at whitespace or `/` and skip comments; tests with `<array >` nesting at 100 and 600 levels.

#### CC-IMPORT-05 Little-endian reads, the 16-byte UUID and the ordered last-wins dictionary are each written more than once
- **Severity:** Low
- **Rule:** `FR-24`, `FR-10`, `FR-77`
- **Evidence:** five little-endian readers ([ProtocolBufferMessage.swift:175-183](../../../Sources/GraphiteCore/NotebookImport/ProtocolBufferMessage.swift#L175-L183) and [TplImage.swift:93-100](../../../Sources/GraphiteCore/NotebookImport/TplImage.swift#L93-L100) line for line, [AppleLZ4Decoder.swift:94-96](../../../Sources/GraphiteCore/NotebookImport/AppleLZ4Decoder.swift#L94-L96), [ZipArchive.swift:209-222](../../../Sources/GraphiteCore/NotebookImport/ZipArchive.swift#L209-L222), `PackedLittleEndianValues`); the UUID from 16 bytes twice ([KeyedArchiveTypedValues.swift:141-146](../../../Sources/GraphiteCore/NotebookImport/KeyedArchiveTypedValues.swift#L141-L146), [PackedLittleEndianValues.swift:23-28](../../../Sources/GraphiteCore/NotebookImport/PackedLittleEndianValues.swift#L23-L28)); the ordered last-wins dictionary twice ([PropertyListValue.swift:43-54](../../../Sources/GraphiteCore/NotebookImport/PropertyListValue.swift#L43-L54), [KeyedArchiveValue.swift:37-48](../../../Sources/GraphiteCore/NotebookImport/KeyedArchiveValue.swift#L37-L48)).
- **Why it matters:** the copies already differ in bounds behaviour (three throw, two rely on the caller, `CC-IMPORT-03`).
- **Fix direction:** one bounds-checked little-endian cursor in its own file; one `UUID(sixteenBytes:)`; one generic ordered dictionary.

#### CC-IMPORT-06 Keyed-archive accessors read a missing required member as an empty value
- **Severity:** Low
- **Rule:** `FR-59`
- **Evidence:** an `NSString` with neither `NS.string` nor `NS.bytes` reads as `""` ([KeyedArchiveTypedValues.swift:71](../../../Sources/GraphiteCore/NotebookImport/KeyedArchiveTypedValues.swift#L71)); an absent `NS.objects` or `NS.keys` reads as `[]` ([:150](../../../Sources/GraphiteCore/NotebookImport/KeyedArchiveTypedValues.swift#L150)), so a damaged `NSArray` or `NSDictionary` reads as empty; Foundation always writes these keys. Introduced in `ef17091`.
- **Why it matters:** a damaged note imports with text or pictures silently missing.
- **Fix direction:** throw `.keyMissing(key:)` when the member key is absent; `""` and `[]` only for members present and empty.

#### CC-IMPORT-07 Two declarations ship with no production reader
- **Severity:** Low
- **Rule:** `FR-82`, `FR-32`
- **Evidence:** `KeyedArchive.archiver` ([KeyedArchive.swift:16](../../../Sources/GraphiteCore/NotebookImport/KeyedArchive.swift#L16)) is read only by a test; `PackedLittleEndianValues.isEmpty` ([PackedLittleEndianValues.swift:8](../../../Sources/GraphiteCore/NotebookImport/PackedLittleEndianValues.swift#L8)) has no caller. Introduced in `ef17091`.
- **Fix direction:** delete `isEmpty`; keep the archiver check inside `init` without storing it.

## 3. Findings: the Goodnotes and Notability readers

#### BUG-IMPORT-01 A Goodnotes notebook without its event log opens as an empty notebook with no issue
- **Severity:** Medium (verdict: Confirmed, traced by the lead)
- **Rule:** `FR-59`
- **Evidence:** traced path, introduced in `2118a0d`: the archive has `schema.pb` but no `index.events.pb` (a damaged central directory, a partial copy); the reader takes the log through `contents(of:)` ([GoodnotesNotebookReader.swift:27](../../../Sources/GraphiteCore/NotebookImport/GoodnotesNotebookReader.swift#L27)), which returns `[]` for any missing entry ([:75-78](../../../Sources/GraphiteCore/NotebookImport/GoodnotesNotebookReader.swift#L75-L78)), a rule its comment justifies for page layers only; no records, no framing failure, so `notebook.pages == []` with no issue.
- **Why it matters:** an import would turn the notebook into an empty one and report success, against the import plan's rule that anything not kept is named in the import report.
- **Fix direction:** a missing event log throws `GoodnotesReadingError.eventLogMissing`; "missing reads as empty" stays on the layer path only, where it is named.

#### BUG-IMPORT-02 A negative stored page width gives a Notability `pageCount` below 1, breaking its "at least 1" contract
- **Severity:** Low (verdict: Confirmed, traced by the lead)
- **Rule:** `FR-68`, `FR-80`
- **Evidence:** the stored `pageWidthInDocumentCoordsKey` may be any real number ([NotabilitySessionReading.swift:90-97](../../../Sources/GraphiteCore/NotebookImport/NotabilitySessionReading.swift#L90-L97)); `NotabilityPageGeometry` only rejects 0 ([NotabilityPageGeometry.swift:26](../../../Sources/GraphiteCore/NotebookImport/NotabilityPageGeometry.swift#L26)), so a negative width gives a negative page height ([:31-33](../../../Sources/GraphiteCore/NotebookImport/NotabilityPageGeometry.swift#L31-L33)) and `pageCount` of floor(y / height) + 1, for example −1 ([NotabilityNoteReader.swift:109-112](../../../Sources/GraphiteCore/NotebookImport/NotabilityNoteReader.swift#L109-L112)), against its doc comment ([:13-16](../../../Sources/GraphiteCore/NotebookImport/NotabilityNoteReader.swift#L13-L16)). The fuzz test already guards with `max(0, …)`. Introduced in `ef17091`.
- **Why it matters:** a caller writing `1...pageCount` traps on a hostile note.
- **Fix direction:** accept only a finite, positive page width; otherwise no geometry and an issue; a malformed-input test.

#### CC-IMPORT-08 Damage to an auxiliary part of a Notability note costs the whole note, ink included
- **Severity:** Medium
- **Rule:** `FR-61`, `FR-59`
- **Evidence:** each of these throws a `NotabilityReadingError`, so no curve can be read: a malformed `Recordings/library.plist` ([NotabilityNoteReader.swift:44-46](../../../Sources/GraphiteCore/NotebookImport/NotabilityNoteReader.swift#L44-L46), pinned by a test), one text run outside the text ([NotabilityTypedTextReading.swift:14](../../../Sources/GraphiteCore/NotebookImport/NotabilityTypedTextReading.swift#L14), [:21-23](../../../Sources/GraphiteCore/NotebookImport/NotabilityTypedTextReading.swift#L21-L23)), one `pageLayoutArray` entry that is not an object ([NotabilitySessionReading.swift:105-108](../../../Sources/GraphiteCore/NotebookImport/NotabilitySessionReading.swift#L105-L108)), playback timing arrays of the wrong length ([NotabilityRecordingReading.swift:44-47](../../../Sources/GraphiteCore/NotebookImport/NotabilityRecordingReading.swift#L44-L47)); for Goodnotes, an unparseable `schema.pb`, which holds only the version, fails the notebook ([GoodnotesNotebookReader.swift:24](../../../Sources/GraphiteCore/NotebookImport/GoodnotesNotebookReader.swift#L24)). The error type's own doc says one damaged picture or shape is not an error, and pictures and shapes follow it. Introduced in `ef17091`.
- **Why it matters:** one corrupt audio index or text run in a lecture note loses every stroke.
- **Fix direction:** these become skipped elements with issues (`recordingsSkipped`, `textRunSkipped`, `pageLayoutSkipped`, `playbackEventsSkipped`), as `readShapes` already does; an unreadable Goodnotes schema is `schemaVersionNotKnown(nil)`.

#### CC-IMPORT-09 A Goodnotes picture, paper or recording whose attachment is missing reads as nil with no issue
- **Severity:** Low
- **Rule:** `FR-59`
- **Evidence:** pictures ([GoodnotesElementDecoder.swift:117](../../../Sources/GraphiteCore/NotebookImport/GoodnotesElementDecoder.swift#L117)), paper ([GoodnotesEventLog.swift:192-198](../../../Sources/GraphiteCore/NotebookImport/GoodnotesEventLog.swift#L192-L198)) and recording audio ([:184](../../../Sources/GraphiteCore/NotebookImport/GoodnotesEventLog.swift#L184)) read as nil when the lookup fails, and no `GoodnotesReadingIssue` names it. Introduced in `2118a0d`.
- **Why it matters:** the importer cannot tell "no image" from "image lost".
- **Fix direction:** `.attachmentNotInLog(identifier:)` and `.paperNotInLog(pageIdentifier:)` where the lookup fails.

#### CC-IMPORT-10 Untrusted relative paths leave the readers as plain strings, with a folder path when the name is absent
- **Severity:** Medium
- **Rule:** `FR-68`, `FR-59`
- **Evidence:** Notability picture, PDF and recording paths ([NotabilityPictureReading.swift:41](../../../Sources/GraphiteCore/NotebookImport/NotabilityPictureReading.swift#L41), `"PDFs/" + (… ?? "")` at [NotabilitySessionReading.swift:112](../../../Sources/GraphiteCore/NotebookImport/NotabilitySessionReading.swift#L112), `"Recordings/" + (… ?? "")` at [NotabilityRecordingReading.swift:30](../../../Sources/GraphiteCore/NotebookImport/NotabilityRecordingReading.swift#L30)) and Goodnotes attachment identifiers ([GoodnotesEventLog.swift:88](../../../Sources/GraphiteCore/NotebookImport/GoodnotesEventLog.swift#L88)) are strings from the file; `../../x` and `/etc/x` are not rejected. Inside the readers they only key a ZIP lookup, which is safe. Introduced in `ef17091` and `2118a0d`.
- **Why it matters:** the converter will name vault files after these values; each converter would have to remember to clean them or write outside the import folder (OBJECTIVE.md: never write outside the vault).
- **Fix direction:** decode them once in Core into a validated `NotebookArchivePath` (no `..`, not absolute, a non-empty name); an invalid path is an issue, an absent one nil.

#### CC-IMPORT-11 The issue list and the error-wrapping helpers exist twice, and the helpers sit in files named for other concepts
- **Severity:** Low
- **Rule:** `FR-10`, `FR-77`
- **Evidence:** `GoodnotesIssueList` ([GoodnotesReadingIssue.swift:62-69](../../../Sources/GraphiteCore/NotebookImport/GoodnotesReadingIssue.swift#L62-L69)) and `NotabilityReadingIssues` ([NotabilityReadingIssue.swift:55-66](../../../Sources/GraphiteCore/NotebookImport/NotabilityReadingIssue.swift#L55-L66)) have the same body; `NotabilityReadingError.readingSession` is declared in `NotabilityInk.swift`, `NotabilitySessionReading.readingElement` in `NotabilityPictureReading.swift` but also used by shapes.
- **Fix direction:** one `NotebookImportIssueList<Issue: Hashable>` in its own file; each wrapper in the file of the type it extends.

#### CC-IMPORT-12 Real-notebook tests are skipped on every machine except the owner's Mac
- **Severity:** Medium
- **Rule:** `FR-93`, `FR-95`
- **Evidence:** both sample suites skip unless two environment variables point at the owner's personal samples ([NotebookImportSamples.swift:3-25](../../../Tests/GraphiteCoreTests/NotebookImportFixtures/NotebookImportSamples.swift#L3-L25)); no `.goodnotes` or `.note` file is in `Tests/`, so CI reads only notebooks the test builders synthesize from the same understanding of the format the readers encode.
- **Why it matters:** a misunderstanding shared by builder and reader passes CI, and the sample comparison in `Coverage.md` cannot be repeated by anyone else.
- **Fix direction:** check in a few small, non-personal notebooks made for the purpose in Goodnotes and Notability, each with its reference counts as a golden file; the personal-sample suite stays opt-in.

#### CC-IMPORT-13 Attachment bytes are returned as whole arrays of up to 512 MiB
- **Severity:** Low
- **Rule:** `FR-105`
- **Evidence:** `contents(of attachment:) -> [UInt8]` ([GoodnotesNotebookReader.swift:69-73](../../../Sources/GraphiteCore/NotebookImport/GoodnotesNotebookReader.swift#L69-L73)) and `fileBytes(relativePath:) -> [UInt8]` ([NotabilityNoteReader.swift:93-95](../../../Sources/GraphiteCore/NotebookImport/NotabilityNoteReader.swift#L93-L95)), up to `maximumEntryBytes`.
- **Why it matters:** importing a long recording or a large PDF copies it into memory; several in a library import can sit in memory at once on an iPad.
- **Fix direction:** a slice of the mapped archive for stored entries; a streaming copy into a caller-owned destination for deflated ones.

#### CC-IMPORT-14 `centre` differs from the codebase's `center`, and an issue comment miscounts its cases
- **Severity:** Low
- **Rule:** `FR-81`, `FR-80`
- **Evidence:** `centre`, `centreLine`, `GoodnotesCentreLine`, `rectangle(centre:)` ([GoodnotesPage.swift:75-98](../../../Sources/GraphiteCore/NotebookImport/GoodnotesPage.swift#L75-L98), [GoodnotesStrokePath.swift:47](../../../Sources/GraphiteCore/NotebookImport/GoodnotesStrokePath.swift#L47)), against `center` in 47 other files; "the last four are parts the reader skipped" is followed by five cases ([GoodnotesReadingIssue.swift:29-31](../../../Sources/GraphiteCore/NotebookImport/GoodnotesReadingIssue.swift#L29-L31)).
- **Fix direction:** `center` throughout; correct the comment.

#### OCP-IMPORT-01 Goodnotes elements of an unknown kind or path layout are dropped, reported once per kind and without the element
- **Severity:** Medium
- **Rule:** `FR-20`, `FR-61`
- **Evidence:** `GoodnotesElementKind` is a failable `Int` enum with no unknown case ([GoodnotesElementDecoder.swift:6-13](../../../Sources/GraphiteCore/NotebookImport/GoodnotesElementDecoder.swift#L6-L13)); unknown kinds and tpl layouts return nil ([GoodnotesLayerReader.swift:81-84](../../../Sources/GraphiteCore/NotebookImport/GoodnotesLayerReader.swift#L81-L84), [GoodnotesStrokePathDecoder.swift:33-35](../../../Sources/GraphiteCore/NotebookImport/GoodnotesStrokePathDecoder.swift#L33-L35)); `GoodnotesElementContent` has no `.unknown` case; the issues carry no element identifier and are de-duplicated, so 200 strokes in a new layout give one issue ([GoodnotesReadingIssue.swift:36-38](../../../Sources/GraphiteCore/NotebookImport/GoodnotesReadingIssue.swift#L36-L38), [:66-68](../../../Sources/GraphiteCore/NotebookImport/GoodnotesReadingIssue.swift#L66-L68)). Introduced in `2118a0d`.
- **Why it matters:** after a Goodnotes update the import report can say only "a format is not known", not how many strokes were lost or where.
- **Fix direction:** `unknown(kind:fields:)` in `GoodnotesElementContent` and `.unknownLayout(formatString:)` for paths, kept in drawing order, with the element identifier in the issue.

#### OCP-IMPORT-02 Format field numbers and keys are written two or three times
- **Severity:** Low
- **Rule:** `FR-24`
- **Evidence:** Goodnotes field numbers appear in `knownFieldNumbers` ([GoodnotesElementDecoder.swift:15-24](../../../Sources/GraphiteCore/NotebookImport/GoodnotesElementDecoder.swift#L15-L24)) and again in the reads ([:58-71](../../../Sources/GraphiteCore/NotebookImport/GoodnotesElementDecoder.swift#L58-L71)); Notability's `"numcurves"`, `"numpoints"` and `"numfractionalwidths"` in `NotabilityInk.swift:45-47` and `NotabilityKnownKeys.swift:34`; the ten `NotabilityPackedArray` raw values restated in `NotabilityKnownKeys.ink`; `"paperSize"`, `"shapes"` and `"NBCPTimeManagerSOANumEventsKey"` twice each.
- **Why it matters:** a field read in one place but missing from the known set gives a false "unknown field" issue.
- **Fix direction:** per-kind `enum …Field: Int, CaseIterable` with `knownFieldNumbers` derived; `enum NotabilitySessionKey: String`, with the known-keys set built from it and `NotabilityPackedArray.allCases`.

#### SRP-IMPORT-01 The Notability decoder also cuts the note into export pages, with two rules for a picture's extent
- **Severity:** Low
- **Rule:** `FR-01`, `FR-05`, `FR-10`
- **Evidence:** `NotabilityInk` answers page-layout queries ([NotabilityInk.swift:112-132](../../../Sources/GraphiteCore/NotebookImport/NotabilityInk.swift#L112-L132)); `page(number:)` places shapes and pictures inline using a picture's turned bounding box ([NotabilityNoteReader.swift:77-86](../../../Sources/GraphiteCore/NotebookImport/NotabilityNoteReader.swift#L77-L86)), while `pageCount` uses its unturned bottom ([:110](../../../Sources/GraphiteCore/NotebookImport/NotabilityNoteReader.swift#L110)).
- **Why it matters:** the decoder changes for layout reasons, and the two extent rules can disagree for a turned picture at the end of a note.
- **Fix direction:** one pure `NotabilityPagePlacement` that the reader calls, with one extent function for both.

## 4. Patterns to keep

- Bounds checks that cannot overflow: counts compared with the bytes left by subtraction and division ([BinaryPropertyList.swift:193](../../../Sources/GraphiteCore/NotebookImport/BinaryPropertyList.swift#L193), [TplImage.swift:89](../../../Sources/GraphiteCore/NotebookImport/TplImage.swift#L89), [AppleLZ4Decoder.swift:40](../../../Sources/GraphiteCore/NotebookImport/AppleLZ4Decoder.swift#L40), [ProtocolBufferMessage.swift:152](../../../Sources/GraphiteCore/NotebookImport/ProtocolBufferMessage.swift#L152)), each tested with 4 GiB and Int64-sized counts.
- Inflate writes into a buffer of exactly the recorded size, refuses a stream that would grow past it, and verifies the CRC-32 ([ZipArchive.swift:181-200](../../../Sources/GraphiteCore/NotebookImport/ZipArchive.swift#L181-L200)).
- A lazy object model, so cycles cannot loop: binary property list members by index, keyed-archive UID chains with a visited set and depth cap ([KeyedArchive.swift:69-82](../../../Sources/GraphiteCore/NotebookImport/KeyedArchive.swift#L69-L82)).
- Partial results with typed causes: a failed layer record, element, picture or shape is skipped with its typed error and the rest of the page returned ([GoodnotesLayerReader.swift:31-53](../../../Sources/GraphiteCore/NotebookImport/GoodnotesLayerReader.swift#L31-L53)); all errors use typed `throws(…)`.
- Work proportional to the page: opening a notebook reads the schema and event log only, and `page(at:)` decodes one layer; Notability curves stay slices, found by binary search.
- External strings decode into enums with `unknown(raw)` ([NotabilityPaper.swift:23-119](../../../Sources/GraphiteCore/NotebookImport/NotabilityPaper.swift#L23-L119), [GoodnotesNotebook.swift:65-115](../../../Sources/GraphiteCore/NotebookImport/GoodnotesNotebook.swift#L65-L115)).
- Seeded fuzz tests over every cut and thousands of byte changes for every format, each asserting a typed error or a value, never a trap.

## 5. Blueprint

Before the converter wires the readers in: make allocation bounds ratio- and platform-aware (`CC-IMPORT-01`, `-02`, `-13`), move the packed-array guard into the type (`CC-IMPORT-03`), turn failed or missing parts into issues (`BUG-IMPORT-01`, `CC-IMPORT-06`, `-08`, `-09`, `OCP-IMPORT-01`), validate archive paths once (`CC-IMPORT-10`), and check in small non-personal golden notebooks (`CC-IMPORT-12`). The converter itself should map both formats into one format-neutral imported-page model and write only ordinary files, as OBJECTIVE.md requires.

## 6. State at 0639588

The import session fixed most findings in `471de62`, `6e21dd0` and `c632468`. Each verdict below was checked in the code at `0639588` against every evidence site of the finding, not only the one the fix names.

| Finding | State | Evidence at `0639588` | Test that pins it |
| --- | --- | --- | --- |
| `CC-IMPORT-01` | Fixed | `checkReadable` refuses a deflated entry declaring more than compressed × 1,032 + 1,024 bytes before `inflate` allocates ([ZipArchive.swift:152-161](../../../Sources/GraphiteCore/NotebookImport/ZipArchive.swift#L152-L161)); the entry limit is 512 MiB on macOS and 256 MiB elsewhere ([NotebookImportLimits.swift:34-38](../../../Sources/GraphiteCore/NotebookImport/NotebookImportLimits.swift#L34-L38)) | `ZipArchiveTests.testAnEntryDeclaringMoreThanDeflateCanProduceIsRefusedBeforeAllocating` (the per-platform limit has no test) |
| `CC-IMPORT-02` | Fixed | a named `maximumPlainValueCount` (250,000) bounds expansion as min(bytes, count) ([PropertyListValue.swift:51-55](../../../Sources/GraphiteCore/NotebookImport/PropertyListValue.swift#L51-L55)), passed by both callers | `BinaryPropertyListTests.testAnExpansionStopsAtTheNamedValueCountBeforeTheByteBudget` |
| `CC-IMPORT-03` | Fixed | the length is checked once in a failable initializer and every read is bounds-checked; no `loadUnaligned` remains ([PackedLittleEndianValues.swift:15-50](../../../Sources/GraphiteCore/NotebookImport/PackedLittleEndianValues.swift#L15-L50)); `LittleEndianBytes` reads throw `readOutsideArchive` | `PackedLittleEndianValuesTests`, `LittleEndianBytesTests` |
| `CC-IMPORT-04` | Partly fixed | tag names end at whitespace or `/`, and comments and CDATA are skipped ([XMLTag.swift:25-38](../../../Sources/GraphiteCore/NotebookImport/XMLTag.swift#L25-L38)). Remains: a processing instruction ends at its first `>`, and the depth is never held at 0 ([PropertyListDocument.swift:58-59](../../../Sources/GraphiteCore/NotebookImport/PropertyListDocument.swift#L58-L59)), so `<?x a>` and N `</array>` let N + 64 real levels pass the pre-scan, against its comment; the check after parsing still catches them; the 600-level test is missing | `BinaryPropertyListTests.testTheXMLNestingScanReadsTagsAsAParserDoes` |
| `CC-IMPORT-05` | Fixed | one checked `LittleEndianInteger.read` used by all five readers, one `UUID(sixteenBytes:)`, one `KeyOrderedDictionary` ([LittleEndianInteger.swift](../../../Sources/GraphiteCore/NotebookImport/LittleEndianInteger.swift), [KeyOrderedDictionary.swift](../../../Sources/GraphiteCore/NotebookImport/KeyOrderedDictionary.swift)) | `LittleEndianIntegerTests`, `KeyOrderedDictionaryTests` |
| `CC-IMPORT-06` | Fixed | absent `NS.string`, `NS.objects` or `NS.keys` throw `keyMissing` ([KeyedArchiveTypedValues.swift:69-74](../../../Sources/GraphiteCore/NotebookImport/KeyedArchiveTypedValues.swift#L69-L74), [:145-146](../../../Sources/GraphiteCore/NotebookImport/KeyedArchiveTypedValues.swift#L145-L146)) | `KeyedArchiveTests.testFoundationObjectsMissingTheirMemberKeyAreDamagedNotEmpty` |
| `CC-IMPORT-07` | Fixed | the archiver name is validated, not stored; `isEmpty` is gone (new test-only members: `CC-IMPORT-16`) | none (a deletion) |
| `BUG-IMPORT-01` | Fixed | a missing `index.events.pb` throws `.eventLogMissing` ([GoodnotesNotebookReader.swift:24](../../../Sources/GraphiteCore/NotebookImport/GoodnotesNotebookReader.swift#L24)); "missing reads as empty" is documented for layers only | `GoodnotesNotebookReaderTests.testANotebookWithoutItsEventLogFailsWithATypedErrorInsteadOfReadingAsEmpty` |
| `BUG-IMPORT-02` | Fixed | only a finite, positive width gives a geometry ([NotabilityPageGeometry.swift:27](../../../Sources/GraphiteCore/NotebookImport/NotabilityPageGeometry.swift#L27)); others are reported as `pageWidthNotUsable` | `NotabilityNoteReaderMalformedInputTests.testAPageWidthThatIsNotFiniteAndPositiveGivesNoPagesAndAnIssue` |
| `CC-IMPORT-08` | Fixed | recordings, text runs, page-layout entries and playback arrays are skipped with issues and the ink is still read; an unreadable Goodnotes schema gives `schemaVersionNotKnown(nil)` | three `NotabilityNoteReaderMalformedInputTests` cases, `GoodnotesNotebookReaderTests.testAnUnreadableSchemaIsReportedAndTheNotebookStillReads` |
| `CC-IMPORT-09` | Fixed | missing attachments report `attachmentNotInLog` and a missing paper `paperNotInLog` ([GoodnotesEventLog.swift:197-211](../../../Sources/GraphiteCore/NotebookImport/GoodnotesEventLog.swift#L197-L211)) | `GoodnotesNotebookReaderTests.testAttachmentsAndPapersMissingFromTheLogAreReported` |
| `CC-IMPORT-10` | Fixed | `NotebookArchivePath` refuses empty, absolute, `.`, `..`, backslash and control characters ([NotebookArchivePath.swift:11-27](../../../Sources/GraphiteCore/NotebookImport/NotebookArchivePath.swift#L11-L27)) and is used for every archive path (the raw Goodnotes identifier stays public: `CC-IMPORT-16`) | `NotebookArchivePathTests`; the climbing-path cases in both reader suites |
| `CC-IMPORT-11` | Fixed | one generic `NotebookImportIssueList`; the wrappers live with their types | none (structural) |
| `CC-IMPORT-12` | Open | the sample suites still skip without the owner's variables, and two more such suites were added (`GoodnotesPagePlannerSampleTests`, `NotabilityPagePlannerSampleTests`, in the skip baseline since `d7fab78`); checking in non-personal notebooks waits for the owner's OK | none |
| `CC-IMPORT-13` | Fixed | a stored entry is a slice of the archive and any entry can be copied in pieces ([ZipArchive.swift:111-148](../../../Sources/GraphiteCore/NotebookImport/ZipArchive.swift#L111-L148), `ZipEntryPieces.swift`); a deflated entry's `data(of:)` still holds two copies (`CC-IMPORT-15`) | `ZipArchiveEntryCopyTests` |
| `CC-IMPORT-14` | Partly fixed | the identifiers are `center` and the miscounting comment is rewritten; `6e21dd0` wrote "centre" again in four doc comments ([GoodnotesNestedFields.swift:49-63](../../../Sources/GraphiteCore/NotebookImport/GoodnotesNestedFields.swift#L49-L63), [GoodnotesElementFields.swift:73](../../../Sources/GraphiteCore/NotebookImport/GoodnotesElementFields.swift#L73)) | none |
| `OCP-IMPORT-01` | Fixed | unknown kinds and path layouts are kept (`.unknown(kind:fieldNumbers:)`, `.unknownLayout`) with the element identifier in the issue ([GoodnotesLayerReader.swift:78-91](../../../Sources/GraphiteCore/NotebookImport/GoodnotesLayerReader.swift#L78-L91)); an unknown element sorts last rather than in drawing order | `GoodnotesNotebookReaderTests.testUnknownKindsFieldsAndPathFormatsAreReportedNotGuessed` |
| `OCP-IMPORT-02` | Fixed | `knownFieldNumbers` derives from per-layout `CaseIterable` enums and the Notability known sets from key enums and `NotabilityPackedArray.allCases`; each literal appears once | `GoodnotesElementKindTests`, `NotabilityKnownKeysTests` |
| `SRP-IMPORT-01` | Partly fixed | `NotabilityPagePlacement` exists and one turned-box extent serves `pageCount` and `page(number:)`; the decoder still does page arithmetic in `curveIndices(onPage:placement:)` ([NotabilityInk.swift:114-132](../../../Sources/GraphiteCore/NotebookImport/NotabilityInk.swift#L114-L132)) | none; no test of a turned picture at the end of a note |

### New findings at 0639588

#### CC-IMPORT-15 A deflated attachment is held twice while it is read
- **Severity:** Low
- **Rule:** `FR-105`
- **Evidence:** `data(of:)` returns `Data(try contents(of: entry))` for a deflated entry ([ZipArchive.swift:113](../../../Sources/GraphiteCore/NotebookImport/ZipArchive.swift#L113)), holding a whole `[UInt8]` and a `Data` copy at once, up to 2 × 256 MiB on iPhone and iPad; callers in `ImportedPagePictures.swift` and `ImportedBackgroundPages.swift`. Introduced in `c632468`.
- **Fix direction:** inflate straight into a `Data` buffer, or copy in pieces to the destination as stored entries already do.

#### CC-IMPORT-16 Members that only tests read stay public, one of them the unchecked archive path
- **Severity:** Low
- **Rule:** `FR-82`, `FR-32`
- **Evidence:** `PackedLittleEndianValues.entryCount` and `entryByteCount` ([PackedLittleEndianValues.swift:9-10](../../../Sources/GraphiteCore/NotebookImport/PackedLittleEndianValues.swift#L9-L10)) are read only by its tests; `GoodnotesAttachment.fileIdentifier` ([GoodnotesNotebook.swift:40](../../../Sources/GraphiteCore/NotebookImport/GoodnotesNotebook.swift#L40)) keeps the raw path from the file beside the checked `file`, so a converter can still reach the unchecked value `CC-IMPORT-10` closed. Introduced in `471de62` and `6e21dd0`.
- **Fix direction:** make them private or remove them; a converter sees only `NotebookArchivePath`.

#### CC-IMPORT-17 The platform entry limit's comment names a source that does not use it
- **Severity:** Low
- **Rule:** `FR-80`
- **Evidence:** [NotebookImportLimits.swift:27-29](../../../Sources/GraphiteCore/NotebookImport/NotebookImportLimits.swift#L27-L29) calls the 256 MiB iPhone and iPad limit "the bounds of the reference readers in `scripts/`", which both use 512 MiB (`scripts/goodnotes-reader.py:25`, `scripts/notability-reader.py:28`). Introduced in `471de62`.
- **Fix direction:** state the rule the limit keeps (an iPad's memory) and pin each platform's value in a test.
