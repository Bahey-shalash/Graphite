# Obsidian Bases: model, expressions, evaluator, index provider, views (BASES)
Snapshot: b13dec3 (main, 2026-10-18).
Scope: `Sources/GraphiteCore/Base*.swift` (13 files), `Sources/GraphiteIndex/BaseRecordQueries.swift`, `Sources/GraphiteIndex/BaseRecordReuse.swift`, `Sources/GraphiteUI/Base*.swift` (11 files), 26 files, 10,841 physical lines, 8,679 code lines (method: blank and comment-only lines and string contents removed by the reconnaissance script).

| Principle | Verdict | Reason |
| --- | --- | --- |
| S | Mixed | `BaseEvaluator` is one class with 14 stored properties and 58 methods across 6 responsibilities; `BaseDocumentModel` has 28 stored properties; link resolution has 5 implementations. The Core value types (`BaseValue`, date support, `BaseHTMLText`, `BaseMapTiles`) are focused. |
| O | Weak | A new view type touches 10 places in 6 files; the function and method vocabulary lives in 12 string `switch`es; `BaseEvaluator.swift` has 41 `default:` branches, 20 of them over the app's own `BaseValue`. |
| L | Weak | The in-memory and index `BaseRecordProvider`s disagree on 4 resolution rules, no contract suite runs both, and about 22 Core test call sites exercise only the in-memory one, which production never uses; a failed index lookup answers `nil`; editor setters do not round-trip keys the parser reads under aliases. |
| I | Mixed | `BaseRecordProvider` has 3 requirements (good); every Bases view takes the whole `VaultStore` and `VaultIndex` actors to use 4 and 5 members; the view writes the model's `actionErrorMessage` and `loadedContentVersion` directly. |
| D | Mixed | The evaluator receives a provider and an environment (good), but omitting the provider silently builds an in-memory one; Core reads `TimeZone.current` through `BaseDateFormatting.displayCalendar` in 6 places; the UI model calls `FileManager.default` and cover images use `URLSession.shared`. |
| Clean code | Mixed | 29 functions exceed 40 code lines (largest 109); 17 owner-less `Task {}` in views and two hand-rolled generation counters; 7 static regular expressions built with `try?`; 4 copies of the frontmatter regular expression; precise, rule-stating comments and strong JavaScript-compatibility helpers. |

## 1. Summary

**What the area does.** Bases reads Obsidian `.base` YAML (and ```` ```base ```` blocks) into `BaseDefinition` ([BaseDefinition.swift:244](../../../Sources/GraphiteCore/BaseDefinition.swift#L244)), parses filter and formula text with a tokenizer and precedence-climbing parser ([BaseExpression.swift:86](../../../Sources/GraphiteCore/BaseExpression.swift#L86), [BaseExpression.swift:278](../../../Sources/GraphiteCore/BaseExpression.swift#L278)), extracts index-checkable conditions ([BaseRecordPrefilter.swift:53](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L53)), loads a bounded batch of records from SQLite ([BaseRecordQueries.swift:22](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L22), [BaseRecordReuse.swift:44](../../../Sources/GraphiteIndex/BaseRecordReuse.swift#L44)), evaluates filters, sorts, groups and summarises in `BaseQueryEngine` ([BaseQuery.swift:125](../../../Sources/GraphiteCore/BaseQuery.swift#L125)) through `BaseEvaluator` ([BaseEvaluator.swift:24](../../../Sources/GraphiteCore/BaseEvaluator.swift#L24)), and publishes the result through the `@MainActor @Observable` `BaseDocumentModel` ([BaseDocumentModel.swift:16](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L16)) to table, cards, list, Kanban and map views. Edits to the `.base` go through a YAML-preserving splicer ([BaseDefinitionEditor.swift:16](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L16)); edits to a note property go through a checked frontmatter rewrite ([BasePropertyEditing.swift:13](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L13)).

Shape: Core holds pure, synchronous logic (13 files, 4,629 code lines by the reconnaissance table); Index holds two SQL files (321 code lines); UI holds 11 files (3,299 code lines). Data flows one way: model → detached task → prefilter → index batch → engine → result → views.

**The three biggest problems.**
1. **One rule, five link resolvers, and they disagree.** Link resolution is implemented by `BaseInMemoryRecordProvider.resolveLinkTarget` ([BaseFileRecord.swift:260](../../../Sources/GraphiteCore/BaseFileRecord.swift#L260)), `VaultIndex.resolvedPaths` ([VaultIndex.swift:365](../../../Sources/GraphiteIndex/VaultIndex.swift#L365)), `BaseEvaluator.resolveLink`'s own rooted pre-check ([BaseEvaluator.swift:158](../../../Sources/GraphiteCore/BaseEvaluator.swift#L158)), `BaseEvaluator.link(_:from:pointsTo:)`'s name fallback ([BaseEvaluator.swift:460](../../../Sources/GraphiteCore/BaseEvaluator.swift#L460)) and `BaseDocumentModel.resolve` ([BaseDocumentModel.swift:433](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L433)). The protocol has no link-kind parameter ([BaseFileRecord.swift:239](../../../Sources/GraphiteCore/BaseFileRecord.swift#L239)). Three defects follow (BUG-BASES-02, -03, -04).
2. **`BaseEvaluator` is a 1,005-code-line interpreter class** holding tree walking, operator semantics, 12 string-dispatched function and method families, per-run caches, link resolution and JavaScript text helpers; its vocabulary is stringly typed and `default:` hides cases (OCP-BASES-01, OCP-BASES-03, SRP-BASES-01).
3. **`BaseDocumentModel` owns everything a base screen does**: definition loading with revision tracking, view selection, query execution with record reuse, `.base` editing, note-property writes with serialisation, link following on the file system, Kanban moves and error reporting through one shared `actionErrorMessage` (SRP-BASES-02, DIP-BASES-01, ISP-BASES-03).

**The three best parts.**
1. **The prefilter is designed as a provable superset**: every SQL condition skips non-ASCII input and lets non-ASCII stored text through so SQLite's ASCII-only case folding can never drop a row the evaluator keeps ([BaseRecordQueries.swift:53-67](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L53-L67), [BaseRecordQueries.swift:99-106](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L99-L106)), and unreadable filters fail closed ([BaseQuery.swift:130-139](../../../Sources/GraphiteCore/BaseQuery.swift#L130-L139)).
2. **`.base` writes cannot silently change meaning**: unchanged files are returned byte for byte, only changed entries are spliced, every output is read back and compared with the edited tree, and a write that would lose a tag or anchor is refused ([BaseDefinitionEditor.swift:60-83](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L60-L83)); saves are revision-checked and keep a byte order mark ([BaseDocumentModel.swift:329-347](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L329-L347), [BaseDocumentModel.swift:634-648](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L634-L648)).
3. **Value semantics are exact and documented**: NaN-reflexive `Hashable` with an exhaustive left-value switch ([BaseValue.swift:341-398](../../../Sources/GraphiteCore/BaseValue.swift#L341-L398)), JavaScript number printing ([BaseValue.swift:426-470](../../../Sources/GraphiteCore/BaseValue.swift#L426-L470)), overflow-checked durations ([BaseValue.swift:42-75](../../../Sources/GraphiteCore/BaseValue.swift#L42-L75)), wall-clock date arithmetic ([BaseDateSupport.swift:163-222](../../../Sources/GraphiteCore/BaseDateSupport.swift#L163-L222)) and stack-depth guards in parser and evaluator ([BaseExpression.swift:281-341](../../../Sources/GraphiteCore/BaseExpression.swift#L281-L341), [BaseEvaluator.swift:185-189](../../../Sources/GraphiteCore/BaseEvaluator.swift#L185-L189)).

**Earlier-pass claims.**

| Claim (source) | Holds? | Evidence |
| --- | --- | --- |
| `BaseRecordProvider` exposes only record, link and backlink reads (`Docs/SOLID.md` I row) | Holds | Three requirements: [BaseFileRecord.swift:234-241](../../../Sources/GraphiteCore/BaseFileRecord.swift#L234-L241). |
| `BaseEvaluator` accepts a record provider (`Docs/SOLID.md` D row) | Holds, with a gap | Parameter at [BaseEvaluator.swift:78](../../../Sources/GraphiteCore/BaseEvaluator.swift#L78), but `nil` silently builds `BaseInMemoryRecordProvider` at [BaseEvaluator.swift:83](../../../Sources/GraphiteCore/BaseEvaluator.swift#L83). |
| Both Bases providers support the same read lookup interface (`Docs/SOLID.md` L row) | Holds for signatures, not for behaviour | 4 semantic differences, LSP-BASES-01. |
| Index provider answers nil/empty and exposes `throwIfLookupFailed()`; `BaseDocumentModel` checks it before publishing (`Docs/SOLID.md` contract evidence) | Holds | [BaseRecordQueries.swift:241-274](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L241-L274), [BaseDocumentModel.swift:215](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L215). |
| `BaseDocumentModel` depends on concrete storage/index actors (`Docs/SOLID.md` D gap) | Holds | [BaseDocumentModel.swift:24-25](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L24-L25). |
| Open work: "shared fixtures exercise both providers' link, alias, ambiguity, backlink, and error semantics" (`Docs/SOLID.md` remaining work) | Still open | The in-memory provider is tested only in [CoreBasesDefinitionQueryEngineTests.swift:213-229](../../../Tests/GraphiteCoreTests/CoreBasesDefinitionQueryEngineTests.swift#L213-L229) and `CoreAreaHandoffTests`; the index provider only in `GraphiteIndexTests`. |
| Links resolved once per folder; re-runs re-read only changed records; unchanged result not redrawn (`Docs/Architecture.md` Bases entry) | Holds | [BaseEvaluator.swift:150-154](../../../Sources/GraphiteCore/BaseEvaluator.swift#L150-L154), [BaseRecordReuse.swift:64](../../../Sources/GraphiteIndex/BaseRecordReuse.swift#L64), [BaseDocumentModel.swift:229](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L229). |
| "Null values count as absent keys, and merge keys apply" (`Docs/Architecture.md`) | Holds for reading, not for editing | Reader applies them ([BaseDefinition.swift:307-311](../../../Sources/GraphiteCore/BaseDefinition.swift#L307-L311)); the editor reads the raw root mapping ([BaseDefinitionEditor.swift:179](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L179), [BaseDefinitionEditor.swift:322](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L322)); see BUG-BASES-05. |
| `.base` edits splice, read back, and refuse an output that changes meaning (`Docs/Architecture.md`) | Holds | [BaseDefinitionEditor.swift:66-81](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L66-L81). |
| Column widths: zero ignored, minimum 40, cap 2,000, written under the full name (`Docs/Architecture.md`) | Holds | [BaseDefinition.swift:188-190](../../../Sources/GraphiteCore/BaseDefinition.swift#L188-L190), [BaseDefinition.swift:419-425](../../../Sources/GraphiteCore/BaseDefinition.swift#L419-L425), [BaseDefinitionEditor.swift:276-290](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L276-L290). |
| Tiles from an ephemeral session without cookies, credentials or disk cache, 4 MB per tile (`Docs/Architecture.md`) | Holds for tiles | [BaseTiledMapView.swift:16](../../../Sources/GraphiteUI/BaseTiledMapView.swift#L16), [BaseTiledMapView.swift:31-38](../../../Sources/GraphiteUI/BaseTiledMapView.swift#L31-L38). Card covers and `image()` URLs use `URLSession.shared` ([BaseValueViews.swift:452](../../../Sources/GraphiteUI/BaseValueViews.swift#L452)), DIP-BASES-04. |
| Card covers downsampled to 640 px under a byte budget (`Docs/Architecture.md`) | Holds | [BaseValueViews.swift:409-410](../../../Sources/GraphiteUI/BaseValueViews.swift#L409-L410), [BaseValueViews.swift:504-517](../../../Sources/GraphiteUI/BaseValueViews.swift#L504-L517). |
| `html()` drops scripts, styles, frames, media, forms; images show `alt`; only web and mail links (`Docs/Architecture.md`) | Holds | [BaseHTMLText.swift:64-71](../../../Sources/GraphiteCore/BaseHTMLText.swift#L64-L71), [BaseHTMLText.swift:331-334](../../../Sources/GraphiteCore/BaseHTMLText.swift#L331-L334), [BaseHTMLText.swift:407-413](../../../Sources/GraphiteCore/BaseHTMLText.swift#L407-L413). |
| Kanban moves go through `BaseDocumentModel.setProperty` (`Docs/Architecture.md`) | Holds | [BaseDocumentModel.swift:563-566](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L563-L566). |
| Unreadable filters fail closed and load no records; missing named view reports the fallback (`Docs/Architecture.md` save boundary) | Holds | [BaseDocumentModel.swift:197-201](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L197-L201), [BaseDocumentModel.swift:155](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L155). |
| Bases in notes show at most 100 rows with a pointer to the full base (`Docs/Architecture.md`) | Holds | [BaseDocumentView.swift:224](../../../Sources/GraphiteUI/BaseDocumentView.swift#L224), [BaseDocumentView.swift:290-305](../../../Sources/GraphiteUI/BaseDocumentView.swift#L290-L305). |
| `date("not a date")` and `duration("soon")` are errors (`Docs/Coverage.md` limitations) | Holds | [BaseEvaluator.swift:741](../../../Sources/GraphiteCore/BaseEvaluator.swift#L741), [BaseEvaluator.swift:761](../../../Sources/GraphiteCore/BaseEvaluator.swift#L761). |

## 2. File inventory

Physical and code lines are the reconnaissance figures; I checked the physical counts against `read_files` (each file's last line number matches).

| File | Physical | Code | Responsible for |
| --- | ---: | ---: | --- |
| [GraphiteCore/BaseColorParsing.swift](../../../Sources/GraphiteCore/BaseColorParsing.swift) | 189 | 153 | CSS and Obsidian colour text to `BaseColorSpecification` |
| [GraphiteCore/BaseDateSupport.swift](../../../Sources/GraphiteCore/BaseDateSupport.swift) | 501 | 397 | Date and duration parsing, wall-clock arithmetic, moment.js formatting and relative text |
| [GraphiteCore/BaseDefinition.swift](../../../Sources/GraphiteCore/BaseDefinition.swift) | 539 | 431 | `.base` model types and the YAML reader (filters, formulas, views, options) |
| [GraphiteCore/BaseDefinitionEditor.swift](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift) | 1142 | 846 | View-editing API plus the generic YAML-preserving splicer and writer (`YAMLSourceLine`, `WrittenYAMLNode`, `RewrittenYAMLWriter`, `YAMLSplicer`) |
| [GraphiteCore/BaseEvaluator.swift](../../../Sources/GraphiteCore/BaseEvaluator.swift) | 1334 | 1113 | Evaluation environment, the interpreter class, and `JavaScriptReplacementTemplate` |
| [GraphiteCore/BaseExpression.swift](../../../Sources/GraphiteCore/BaseExpression.swift) | 500 | 416 | Expression AST, tokenizer, parser, `dependsOnCurrentRow` |
| [GraphiteCore/BaseFileRecord.swift](../../../Sources/GraphiteCore/BaseFileRecord.swift) | 304 | 233 | Frontmatter node model and typing, `BaseFileRecord`, `BaseRecordProvider`, in-memory provider |
| [GraphiteCore/BaseHTMLText.swift](../../../Sources/GraphiteCore/BaseHTMLText.swift) | 447 | 365 | Tolerant `html()` reader into styled runs |
| [GraphiteCore/BaseMapTiles.swift](../../../Sources/GraphiteCore/BaseMapTiles.swift) | 98 | 59 | `mapTiles` background classification and tile URL templates |
| [GraphiteCore/BasePropertyEditing.swift](../../../Sources/GraphiteCore/BasePropertyEditing.swift) | 103 | 73 | Checked single-property frontmatter rewrite |
| [GraphiteCore/BaseQuery.swift](../../../Sources/GraphiteCore/BaseQuery.swift) | 486 | 397 | Result types, `BaseQueryEngine` (filter, sort, limit, group, cells, presentation), built-in summaries, coordinates |
| [GraphiteCore/BaseRecordPrefilter.swift](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift) | 169 | 126 | Extraction of index-checkable requirements from filters |
| [GraphiteCore/BaseValue.swift](../../../Sources/GraphiteCore/BaseValue.swift) | 591 | 450 | Value enum and its parts (date, duration, link, object, regular expression), equality, text, ordering |
| [GraphiteIndex/BaseRecordQueries.swift](../../../Sources/GraphiteIndex/BaseRecordQueries.swift) | 338 | 252 | Prefilter SQL, record loading, index provider, lookup failure box, fast scalar decode |
| [GraphiteIndex/BaseRecordReuse.swift](../../../Sources/GraphiteIndex/BaseRecordReuse.swift) | 86 | 69 | Reusing loaded records whose index row is unchanged |
| [GraphiteUI/BaseCardsAndListViews.swift](../../../Sources/GraphiteUI/BaseCardsAndListViews.swift) | 182 | 161 | Cards and list layouts, group header |
| [GraphiteUI/BaseDocumentModel.swift](../../../Sources/GraphiteUI/BaseDocumentModel.swift) | 666 | 505 | Observable state and every load, query and write a base screen makes |
| [GraphiteUI/BaseDocumentView.swift](../../../Sources/GraphiteUI/BaseDocumentView.swift) | 592 | 494 | Document and embedded entry views, embedded model cache, container, banners, toolbar |
| [GraphiteUI/BaseEmbedding.swift](../../../Sources/GraphiteUI/BaseEmbedding.swift) | 111 | 87 | Embed context, code-block and file-embed views |
| [GraphiteUI/BaseKanbanView.swift](../../../Sources/GraphiteUI/BaseKanbanView.swift) | 199 | 166 | Kanban board, drag and Move To |
| [GraphiteUI/BaseMapView.swift](../../../Sources/GraphiteUI/BaseMapView.swift) | 310 | 260 | Map view, camera rules, markers, notices |
| [GraphiteUI/BasePropertyEditorSheet.swift](../../../Sources/GraphiteUI/BasePropertyEditorSheet.swift) | 263 | 224 | Property editor sheet and `BasePropertyDraft` |
| [GraphiteUI/BaseTableView.swift](../../../Sources/GraphiteUI/BaseTableView.swift) | 323 | 267 | Table, header sort, column resize |
| [GraphiteUI/BaseTiledMapView.swift](../../../Sources/GraphiteUI/BaseTiledMapView.swift) | 278 | 223 | Raster tile overlay, tile session, `MKMapView` bridge |
| [GraphiteUI/BaseValueViews.swift](../../../Sources/GraphiteUI/BaseValueViews.swift) | 613 | 515 | Cell and value views, `html()` view, cover images, `BaseThumbnailStore`, Lucide icon map, marker colours |
| [GraphiteUI/BaseViewEditorSheet.swift](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift) | 477 | 397 | View draft, draft-versus-file state, view editor sheet |
| **Total (26 files)** | **10841** | **8679** | |

## 3. Responsibility maps of the major types

### 3.1 `BaseEvaluator` ([BaseEvaluator.swift:24-1223](../../../Sources/GraphiteCore/BaseEvaluator.swift#L24-L1223), 1,005 code lines)

**Stored state (14 instance properties, counted by reading lines 25-43):**

| Group | Properties |
| --- | --- |
| Inputs | `environment` (25), `thisRecord` (26), `provider` (27), `parsedFormulas` (28) |
| Record lookup memo | `recordsByPath` (29), `missingRecordPaths` (30), `resolvedLinks` (34), `backlinksByPath` (35) |
| Parse and compile memo | `parsedSources` (31), `compiledRegularExpressions` (41), `declaredTypesByKey` (38) |
| Formula memo and cycle detection | `formulaResults` (32), `formulasInProgress` (33) |
| Recursion guard | `evaluationDepth` (43) |

Static limits: `maximumListOperationLength` 100,000 (45), `maximumPairwiseUniqueLength` 10,000 (49), `unconditionalEvaluationDepth` 16 (52), `minimumStackHeadroomBytes` 128 KiB (56).

**Functions (58 methods, counted by reading), grouped:**

| Responsibility | Members (line) |
| --- | --- |
| Public entry points | `init` (78), `parsed` (97), `evaluate(_:for:)` (104), `evaluate(sourceText:for:)` (108), `value(of:for:)` (113), `matches` (123), `evaluateSummary` (141), `resolveLink` (146), `record(at:)` (167) |
| Tree walking and scope | `evaluate(_:in:)` (180), `currentThreadHasStackHeadroom` (244), `identifierValue` (255), `memberValue` (266), `thisMember` (283), `field` (292), `astronomicalYear` (342), `millisecondOfSecond` (350), `subscriptValue` (357) |
| Properties, files, formulas | `noteProperty` (380), `noteObject` (385), `declaredType` (392), `formulaValue` (399), `fileField` (416), `linkTargets` (438), `internalBodyLinks` (446), `backlinks` (450) |
| Link identity | `link(_:from:pointsTo:)` (460), `normalizedLinkText` (469), `filePath(of:from:)` (476) |
| Operators and coercion | `isEqual` (494), `binaryValue` (531), `millisecondsIfComparedWithNumber` (554), `duration(from:)` (559), `addition` (568), `concatenatedText` (593), `subtraction` (600), `multiplicative` (622), `numberValue` (646), `javaScriptFixed` (658), `javaScriptNumber` (695), `arithmeticNumber` (705) |
| Global functions | `callFunction` (716, 109 code lines, 16 names) |
| Methods by receiver | `callMethod` (835), `typedMethod` (858), `compiledRegularExpression` (883), `stringMethod` (892), `regularExpressionSplit` (956), `matches(of:in:)` (979), `sliceRange` (990), `numberMethod` (1003), `listMethod` (1028), `uniqueElements` (1081), `listCallback` (1102), `dateMethod` (1130), `fileMethod` (1143), `linkMethod` (1183), `normalizedFolderPath` (1200) |
| Error wording | `describe` (1205), `capitalizedFirstLetter` (1226) |

Nested types: `FormulaKey` (58), `LinkKey` (65), `Scope` (70), `UniqueKey` (1060). The file also holds `JavaScriptReplacementTemplate` ([BaseEvaluator.swift:1232-1334](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1232-L1334)) and `BaseEvaluationEnvironment` ([BaseEvaluator.swift:4-19](../../../Sources/GraphiteCore/BaseEvaluator.swift#L4-L19)).

**Calls that cross responsibilities (the coupling a split must preserve):**
- Operators call link resolution: `isEqual` resolves both sides of link/file comparisons ([BaseEvaluator.swift:505-517](../../../Sources/GraphiteCore/BaseEvaluator.swift#L505-L517)), so equality needs the record-lookup memo.
- List methods call operators: `contains`, `containsAll`, `containsAny` and `unique` use `isEqual` ([BaseEvaluator.swift:1029](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1029), [BaseEvaluator.swift:1096](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1096)).
- Method dispatch calls the tree walker: `listCallback` evaluates its argument expression per element with a new scope ([BaseEvaluator.swift:1108-1113](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1108-L1113)).
- Field access calls link resolution and record lookup: `field(.link)` ([BaseEvaluator.swift:298-300](../../../Sources/GraphiteCore/BaseEvaluator.swift#L298-L300)), `fileField` ([BaseEvaluator.swift:416-435](../../../Sources/GraphiteCore/BaseEvaluator.swift#L416-L435)).
- Outside callers use the memo directly: `BaseQueryEngine.groupIdentity`, the Unique summary and `imageReference` call `evaluator.resolveLink` and `evaluator.record(at:)` ([BaseQuery.swift:321](../../../Sources/GraphiteCore/BaseQuery.swift#L321), [BaseQuery.swift:340-342](../../../Sources/GraphiteCore/BaseQuery.swift#L340-L342), [BaseQuery.swift:390-397](../../../Sources/GraphiteCore/BaseQuery.swift#L390-L397)); `BaseRecordPrefilter` uses `parsed` and `evaluate` ([BaseRecordPrefilter.swift:60](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L60), [BaseRecordPrefilter.swift:100](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L100)).

**Lifecycle and ordering rules it relies on:**
- One evaluator per query run, used from one thread: the class is not thread-safe and its caches assume one index snapshot ([BaseEvaluator.swift:21-23](../../../Sources/GraphiteCore/BaseEvaluator.swift#L21-L23)).
- `knownRecords` are consulted before the provider; `thisRecord` is appended to them ([BaseEvaluator.swift:81-84](../../../Sources/GraphiteCore/BaseEvaluator.swift#L81-L84)).
- A link's resolution depends on its source only through the folder; the cache key is the folder ([BaseEvaluator.swift:150-153](../../../Sources/GraphiteCore/BaseEvaluator.swift#L150-L153)). Any provider that violates this makes cached answers wrong.
- `evaluationDepth` and `formulasInProgress` are balanced by `defer` ([BaseEvaluator.swift:185-186](../../../Sources/GraphiteCore/BaseEvaluator.swift#L185-L186), [BaseEvaluator.swift:404-405](../../../Sources/GraphiteCore/BaseEvaluator.swift#L404-L405)); a split must keep one shared depth counter across formula references and callbacks.
- Formula results are memoised per (record path, name), so a formula must not depend on per-call scope variables ([BaseEvaluator.swift:400-413](../../../Sources/GraphiteCore/BaseEvaluator.swift#L400-L413)).

**Verdict:** too many reasons to change in one type; the interpreter core (walk, scope, depth guard) is sound and must stay one unit. **Proposed split** (each a file named after its type):

| New type | Members moved | Kind |
| --- | --- | --- |
| `BaseRecordLookup` (final class, per run) | `recordsByPath`, `missingRecordPaths`, `resolvedLinks`, `backlinksByPath`, `record(at:)`, `resolveLink`, `backlinks`, `linkTargets`, `internalBodyLinks`, `link(_:from:pointsTo:)`, `filePath(of:from:)` | Memo over the provider; the one owner of link identity inside a run |
| `BaseFormulaTable` | `parsedFormulas`, `formulaResults`, `formulasInProgress`, `formulaValue` | Formula memo and cycle detection |
| `BaseValueOperators` (struct over a `BaseRecordLookup`) | `isEqual`, `binaryValue`, `addition`, `subtraction`, `multiplicative`, coercion helpers | Operator semantics |
| `BaseFunctionLibrary` keyed by a `BaseFunctionName` enum | the 16 cases of `callFunction` | Global functions |
| `BaseTextMethods`, `BaseNumberMethods`, `BaseListMethods`, `BaseDateMethods`, `BaseFileMethods`, `BaseLinkMethods` keyed by a `BaseMethodName` enum | `stringMethod`, `numberMethod`, `listMethod`/`uniqueElements`/`listCallback`, `dateMethod`, `fileMethod`, `linkMethod` | Methods by receiver |
| `JavaScriptText` (enum) | `javaScriptFixed`, `javaScriptNumber`, `regularExpressionSplit`, `JavaScriptReplacementTemplate`, `sliceRange` | JavaScript string and number semantics |
| `StackHeadroom` (enum, primitives file) | `currentThreadHasStackHeadroom` | Platform primitive |
| `BaseEvaluator` (kept) | `evaluate(_:in:)`, `identifierValue`, `memberValue`, `thisMember`, `field`, `subscriptValue`, `noteProperty`, `noteObject`, public entry points | Interpreter |

### 3.2 `BaseDocumentModel` ([BaseDocumentModel.swift:16-611](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L16-L611), 456 code lines)

**Stored state (28 instance properties, counted by reading lines 21-67):**

| Group | Properties (line) |
| --- | --- |
| Identity and dependencies | `source` (21), `contextPath` (23), `store` (24), `index` (25), `didSaveFile` (27) |
| Loaded definition | `definition` (29), `loadErrorMessage` (30), `declaredTypes` (40), `declaredTypesByFoldedName` (42), `sourceRevision` (52), `parsedSourceText` (55), `reloadGeneration` (58) |
| View selection and sort | `viewSelectionErrorMessage` (31), `selectedViewIndex` (37), `sortOverride` (39), `preferredViewName` (56) |
| Query execution | `result` (32), `candidateCount` (33), `loadedRecordCount` (34), `isLoading` (35), `availablePropertyKeys` (49), `queryGeneration` (59), `runningQuery` (61), `loadedRecords` (64), `loadedContentVersion` (67) |
| Property writes | `requestedCheckboxValues` (45), `propertyWrites` (47) |
| Shared outcome channel | `actionErrorMessage` (36) |

**Functions grouped by responsibility:**

| Responsibility | Members (line) |
| --- | --- |
| Load and parse | `reload` (92, 51 code lines), `restoreSelection` (146) |
| Run the selected view | `runQuery` (177, 62 code lines), `QueryOutcome` (245), `hasSameContent` (253) |
| Select and sort | `selectView(named:)` (261), `selectView(_:)` (273), `toggleSort` (286), `sortOverride(afterTappingHeaderOf:…)` (291), `setSort` (300), `resetSort` (305), `effectiveSort` (84) |
| Edit the `.base` file | `canEditDefinition` (313), `editDefinition` (325), `selectView(atPosition:)` (363), `saveSortToView` (369), `setColumnWidth` (383), `addView` (389), `duplicateSelectedView` (396), `deleteView` (406), `uniqueViewName` (420) |
| Follow links | `resolve` (433), `isRegularFile` (441) |
| Edit note properties | `canEdit` (453), `canEditValue` (461), `editorKind` (474), `foldedPropertyName` (494), `toggleCheckbox` (500), `setProperty` (517), `writtenPropertyNode` (598) |
| Kanban | `canMoveToGroup` (553), `moveToGroup` (563), `propertyValue(forGroupKey:)` (571) |

Helper types in the same file: `BaseViewTarget` (615), `UTF8FileText` (634), `BasePropertyEditorKind` (650), `BaseViewType.defaultViewName` (654).

**Calls that cross responsibilities:**
- `editDefinition` calls `reload` both on a revision mismatch and after saving ([BaseDocumentModel.swift:331](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L331), [BaseDocumentModel.swift:350](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L350)); `reload` always ends in `runQuery` ([BaseDocumentModel.swift:143](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L143)).
- `setProperty` saves the note, calls `didSaveFile`, refreshes the index directly, then runs the query ([BaseDocumentModel.swift:529-543](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L529-L543)).
- `deleteView` re-selects and runs the query a second time after `editDefinition`'s reload already did ([BaseDocumentModel.swift:411-416](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L411-L416)).
- Every responsibility writes `actionErrorMessage`; `runQuery` clears it on success ([BaseDocumentModel.swift:233](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L233)); the view reads and clears it to move it into a sheet ([BaseDocumentView.swift:314-318](../../../Sources/GraphiteUI/BaseDocumentView.swift#L314-L318)).

**Lifecycle and ordering rules:**
- `sourceRevision`, `parsedSourceText`, `declaredTypes` and `definition` must be set together and only by the newest reload ([BaseDocumentModel.swift:116-125](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L116-L125)); `sourceRevision` must keep naming the old text until the post-save reload ([BaseDocumentModel.swift:344-347](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L344-L347)).
- A failing reload must cancel the running query and bump `queryGeneration` before clearing state ([BaseDocumentModel.swift:133-138](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L133-L138)).
- `sortOverride` must be reset whenever the selected view changes or disappears ([BaseDocumentModel.swift:157](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L157), [BaseDocumentModel.swift:171](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L171), [BaseDocumentModel.swift:278](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L278)).
- `loadedRecords` is replaced only by a published run of the newest generation ([BaseDocumentModel.swift:226-227](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L226-L227)).
- `provider.throwIfLookupFailed()` must run after `engine.run` and before the outcome is returned ([BaseDocumentModel.swift:212-215](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L212-L215)).
- Property writes are serialised by chaining `propertyWrites` ([BaseDocumentModel.swift:503-509](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L503-L509)).
- The view must set `loadedContentVersion` after a successful reload ([BaseDocumentView.swift:242-247](../../../Sources/GraphiteUI/BaseDocumentView.swift#L242-L247)), a "call X after Y" rule held by the caller.

**Verdict:** an aggregate of five workflows sharing one error field. **Proposed split:**

| New type | Responsibility | Members moved |
| --- | --- | --- |
| `BaseDefinitionFile` (struct over a narrow store capability) | Read, decode with BOM, parse, revision-check, apply an editor change, save | `UTF8FileText`, the read/parse half of `reload`, the body of `editDefinition` |
| `BaseViewSelection` (value type) | Selected view, sort override, preferred name, restore rules, header-tap cycle | `selectedViewIndex`, `sortOverride`, `preferredViewName`, `viewSelectionErrorMessage`, `restoreSelection`, `sortOverride(afterTappingHeaderOf:…)` |
| `BaseQueryRun` (nonisolated function plus a `LatestRequest` primitive) | Inputs → `QueryOutcome` off the main actor; latest answer wins | Body of the detached task in `runQuery`, `hasSameContent` |
| `BaseNotePropertyWriter` | Serialised, revision-checked property writes and checkbox requests | `setProperty`, `toggleCheckbox`, `requestedCheckboxValues`, `propertyWrites`, `writtenPropertyNode`, `propertyValue(forGroupKey:)` |
| `BaseDocumentModel` (kept, observable) | Published state and one intent method per UI event; errors returned as typed values | remaining state and intents |

### 3.3 `BaseDefinitionEditor.swift` (846 code lines, 5 types)

| Type | Lines | Stored state | Responsibility |
| --- | --- | --- | --- |
| `BaseDefinitionEditor` | [16-366](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L16-L366) | `rootMapping`, `originalText`, `originalTree`, `lineEnding`, `refusedEdit` | Bases-specific edit operations (14 public or internal mutators) and the write pipeline `yaml()` |
| `YAMLSourceLine` | [391-416](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L391-L416) | `content`, `terminator` | Line splitting as libyaml counts |
| `WrittenYAMLNode` | [423-578](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L423-L578) | 9 properties | Meaning-plus-form snapshot of a Yams tree |
| `RewrittenYAMLWriter` | [590-791](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L590-L791) | 6 properties | Writes changed nodes keeping anchors, aliases, tags and flow style |
| `YAMLSplicer` | [798-1142](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L798-L1142) | 3 properties | Splices changed entries into original lines |

Ordering rules: `WrittenYAMLNode` must be built while the `Yams.Parser` is alive, because anchors die with it ([BaseDefinitionEditor.swift:43-45](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L43-L45)); writer nodes need fresh tag objects because Yams resolves tags in place ([BaseDefinitionEditor.swift:657-658](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L657-L658)); `refusedEdit` set by `addView` is thrown only at `yaml()` ([BaseDefinitionEditor.swift:61](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L61), [BaseDefinitionEditor.swift:187-190](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L187-L190)), an outcome carried in a field.

**Verdict:** the four YAML types are generic, well-built infrastructure filed under a Bases name. **Proposed split:** move `YAMLSourceLine`, `WrittenYAMLNode`, `RewrittenYAMLWriter`, `YAMLSplicer` and `serializedYAML` into a `YAMLPreservingWriter` group of files (one type per file) with a single entry point `YAMLPreservingWriter.text(original:originalTree:edited:)`; `BaseDefinitionEditor` keeps the view operations and calls it. `addView` should throw like every other mutator instead of storing `refusedEdit`.

### 3.4 `BaseHTMLText` reader ([BaseHTMLText.swift:62-447](../../../Sources/GraphiteCore/BaseHTMLText.swift#L62-L447), 328 code lines)

The private `Parser` has 9 stored properties (lines 107-118) and one responsibility: turn markup into styled runs. Element vocabularies are declared once as sets ([BaseHTMLText.swift:64-82](../../../Sources/GraphiteCore/BaseHTMLText.swift#L64-L82)). `readTag` (52 code lines) and `openElement` (52 code lines) are long but single-purpose. **Verdict:** keep as one type; extract attribute scanning from `readTag` into `scanAttributes()` to bring both under 40 lines.

## 4. Findings by principle

### S

#### SRP-BASES-01 `BaseEvaluator` interprets, coerces, dispatches 16 functions and 6 method families, memoises lookups and formats errors in one class
- **Severity:** Medium
- **Evidence:** 14 stored properties and 58 methods (section 3.1, counted by reading [BaseEvaluator.swift:25-43](../../../Sources/GraphiteCore/BaseEvaluator.swift#L25-L43) and every `func` to line 1222). `callFunction` is 109 code lines ([BaseEvaluator.swift:716-831](../../../Sources/GraphiteCore/BaseEvaluator.swift#L716-L831)); `stringMethod` 55 ([BaseEvaluator.swift:892-951](../../../Sources/GraphiteCore/BaseEvaluator.swift#L892-L951)); `evaluate(_:in:)` 56 ([BaseEvaluator.swift:180-239](../../../Sources/GraphiteCore/BaseEvaluator.swift#L180-L239)); `field` 45 ([BaseEvaluator.swift:292-337](../../../Sources/GraphiteCore/BaseEvaluator.swift#L292-L337)). The same file carries `BaseEvaluationEnvironment` and `JavaScriptReplacementTemplate` ([BaseEvaluator.swift:4-19](../../../Sources/GraphiteCore/BaseEvaluator.swift#L4-L19), [BaseEvaluator.swift:1232-1334](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1232-L1334)).
- **Why it matters:** every new Obsidian function, every coercion fix and every link-rule fix edits the same 1,334-line file; three commits touched it (reconnaissance). The JavaScript helpers (`javaScriptFixed`, `regularExpressionSplit`) and link identity cannot be tested or reused without constructing an evaluator with a provider.
- **Fix direction:** split along section 3.1: `BaseRecordLookup`, `BaseFormulaTable`, `BaseValueOperators`, typed function and method libraries, `JavaScriptText`; the interpreter keeps walking, scope and the depth guard.

#### SRP-BASES-02 `BaseDocumentModel` holds 28 stored properties for five workflows and one shared error field
- **Severity:** Medium
- **Evidence:** section 3.2; state at [BaseDocumentModel.swift:21-67](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L21-L67); `runQuery` 62 code lines ([BaseDocumentModel.swift:177-243](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L177-L243)), `reload` 51 ([BaseDocumentModel.swift:92-144](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L92-L144)). Writes to `actionErrorMessage` at 233, 237, 353, 531, 544 and from the view at [BaseDocumentView.swift:316](../../../Sources/GraphiteUI/BaseDocumentView.swift#L316), [BaseDocumentView.swift:458](../../../Sources/GraphiteUI/BaseDocumentView.swift#L458), [BaseDocumentView.swift:460](../../../Sources/GraphiteUI/BaseDocumentView.swift#L460) (8 writers, counted by reading).
- **Why it matters:** a property-write error, a link-follow error and a `.base` edit error share one field that any successful query clears ([BaseDocumentModel.swift:233](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L233)), so an error's visibility depends on what finishes next. The model cannot be tested without a real `VaultStore` and `VaultIndex` on disk ([UiBasesDocumentModelTests.swift:12-17](../../../Tests/GraphiteUITests/UiBasesDocumentModelTests.swift#L12-L17)).
- **Fix direction:** the split in section 3.2; intent methods return typed outcomes, and the model turns each into its own published field.

#### SRP-BASES-03 Link resolution has five implementations with different rules
- **Severity:** High
- **Evidence:** (1) [BaseFileRecord.swift:260-282](../../../Sources/GraphiteCore/BaseFileRecord.swift#L260-L282) in-memory; (2) [VaultIndex.swift:365-402](../../../Sources/GraphiteIndex/VaultIndex.swift#L365-L402) index; (3) `resolveLink`'s rooted-record pre-check when there is no source ([BaseEvaluator.swift:158-159](../../../Sources/GraphiteCore/BaseEvaluator.swift#L158-L159)) and `filePath`'s rooted pre-check ([BaseEvaluator.swift:484](../../../Sources/GraphiteCore/BaseEvaluator.swift#L484)); (4) the unresolved-name fallback in `link(_:from:pointsTo:)` and `hasLink` ([BaseEvaluator.swift:460-466](../../../Sources/GraphiteCore/BaseEvaluator.swift#L460-L466), [BaseEvaluator.swift:1174-1177](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1174-L1177)); (5) `BaseDocumentModel.resolve`, root path on disk first, then the index ([BaseDocumentModel.swift:433-445](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L433-L445)). The index rule is "beside the note, then from the vault root" ([MarkdownSemantics.swift:877-903](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L877-L903)).
- **Why it matters:** the five disagree in observable ways: BUG-BASES-02 (link kind dropped), BUG-BASES-03 (prefilter versus evaluator), BUG-BASES-04 (tap versus cell). Every fix to Obsidian link semantics must be made up to five times.
- **Fix direction:** one `BaseLinkResolution` owner per run (inside `BaseRecordLookup`) that takes the link kind and the source folder and is the only caller of the provider; `BaseDocumentModel.resolve` asks the same provider instead of the file system.

#### SRP-BASES-04 Image-reference and colour classification is decided in Core and again in the view
- **Severity:** Low
- **Evidence:** `BaseQueryEngine.imageReference` ([BaseQuery.swift:378-401](../../../Sources/GraphiteCore/BaseQuery.swift#L378-L401)) with its own hex pattern ([BaseQuery.swift:405](../../../Sources/GraphiteCore/BaseQuery.swift#L405)); `BaseImageValueView.reference(for:)` re-classifies the same text with `BaseColorParsing` and a URL scheme check ([BaseValueViews.swift:305-310](../../../Sources/GraphiteUI/BaseValueViews.swift#L305-L310)); a third hex rule decides tag versus colour ([BaseValueViews.swift:143-148](../../../Sources/GraphiteUI/BaseValueViews.swift#L143-L148)). `BaseQueryEngine.cell` resolves only vault links and leaves URLs and colours for the view ([BaseQuery.swift:196-198](../../../Sources/GraphiteCore/BaseQuery.swift#L196-L198)).
- **Why it matters:** a cover accepted by the card path (`#abc` via the regex) and an `image()` value checked by `BaseColorParsing` can disagree, and the view-side rule is untested outside UI tests.
- **Fix direction:** `BaseQueryEngine` produces a typed `BaseImageReference` in the cell for every `image()` value; views render it and decide nothing.

#### SRP-BASES-05 `BaseQuery.swift` mixes the engine with result types, summaries and coordinate parsing
- **Severity:** Low
- **Evidence:** result types ([BaseQuery.swift:4-108](../../../Sources/GraphiteCore/BaseQuery.swift#L4-L108)), `BaseCoordinate` parsing used also by the vault map ([BaseQuery.swift:20-53](../../../Sources/GraphiteCore/BaseQuery.swift#L20-L53), [PlacedNote.swift:61](../../../Sources/GraphiteCore/PlacedNote.swift#L61)), the engine ([BaseQuery.swift:112-420](../../../Sources/GraphiteCore/BaseQuery.swift#L112-L420)), `BaseSummaryCalculator` ([BaseQuery.swift:423-486](../../../Sources/GraphiteCore/BaseQuery.swift#L423-L486)).
- **Why it matters:** `BaseCoordinate` is a vault-map dependency found by grepping a query file; the file name hides four concepts.
- **Fix direction:** one concept per file: `BaseQueryResult.swift`, `BaseCoordinate.swift`, `BaseQueryEngine.swift`, `BaseSummaryCalculator.swift`.

### O

#### OCP-BASES-01 The expression vocabulary is spread across 14 string `switch`es
- **Severity:** Medium
- **Evidence:** function names in `callFunction` ([BaseEvaluator.swift:728-830](../../../Sources/GraphiteCore/BaseEvaluator.swift#L728-L830)); generic methods ([BaseEvaluator.swift:843-853](../../../Sources/GraphiteCore/BaseEvaluator.swift#L843-L853)); callback names ([BaseEvaluator.swift:838](../../../Sources/GraphiteCore/BaseEvaluator.swift#L838)); object and regular-expression methods ([BaseEvaluator.swift:867-873](../../../Sources/GraphiteCore/BaseEvaluator.swift#L867-L873)); text, number, list, callback, date, file and link methods ([BaseEvaluator.swift:894](../../../Sources/GraphiteCore/BaseEvaluator.swift#L894), [1004](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1004), [1031](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1031), [1104](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1104), [1131](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1131), [1145](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1145), [1184](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1184)); the null-receiver rule by name prefix ([BaseEvaluator.swift:854](../../../Sources/GraphiteCore/BaseEvaluator.swift#L854)); prefilter copies of method names ([BaseRecordPrefilter.swift:110-127](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L110-L127), [BaseRecordPrefilter.swift:146](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L146)). 12 in the evaluator plus 2 in the prefilter, counted by reading.
- **Why it matters:** adding `file.hasLinkTo()` or renaming a method means finding every string; the prefilter's superset guarantee depends on its list matching the evaluator's null behaviour by hand (`hasPrefix("has")` returns false for any unknown `has…` method on null, [BaseEvaluator.swift:854](../../../Sources/GraphiteCore/BaseEvaluator.swift#L854)). The rule "vocabularies are one typed enum" is missing here.
- **Fix direction:** `BaseFunctionName` and `BaseMethodName` enums parsed once from the identifier, each case carrying its arity and its null-receiver result; the prefilter switches over the same enums.

#### OCP-BASES-02 A new view type touches 10 places in 6 files
- **Severity:** Medium
- **Evidence:** (1) enum, `init(rawValue:)`, `rawValue` [BaseDefinition.swift:86-114](../../../Sources/GraphiteCore/BaseDefinition.swift#L86-L114); (2) per-type option structs and parsing [BaseDefinition.swift:192-194](../../../Sources/GraphiteCore/BaseDefinition.swift#L192-L194), [BaseDefinition.swift:427-429](../../../Sources/GraphiteCore/BaseDefinition.swift#L427-L429); (3) `presentation` switch with `default:` [BaseQuery.swift:356-373](../../../Sources/GraphiteCore/BaseQuery.swift#L356-L373); (4) `defaultViewName` [BaseDocumentModel.swift:654-665](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L654-L665); (5) `systemImage` [BaseValueViews.swift:602-612](../../../Sources/GraphiteUI/BaseValueViews.swift#L602-L612); (6) `resultView` switch [BaseDocumentView.swift:426-447](../../../Sources/GraphiteUI/BaseDocumentView.swift#L426-L447); (7) New View menu list [BaseDocumentView.swift:562](../../../Sources/GraphiteUI/BaseDocumentView.swift#L562); (8) user text listing the types [BaseDocumentView.swift:407](../../../Sources/GraphiteUI/BaseDocumentView.swift#L407); (9) `editableTypes` [BaseViewEditorSheet.swift:168](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L168); (10) per-type editor sections [BaseViewEditorSheet.swift:268-269](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L268-L269). Map-only checks add two more ([BaseDocumentView.swift:226](../../../Sources/GraphiteUI/BaseDocumentView.swift#L226), [BaseDocumentView.swift:322](../../../Sources/GraphiteUI/BaseDocumentView.swift#L322)).
- **Why it matters:** Kanban was added in 1.14 and needed all of these; lists (7) and (9) are two hand-kept copies of "types the user can create" that already exist as one enum.
- **Fix direction:** a `BaseViewKind` descriptor per supported type (raw name, default name, symbol, option parser, presentation builder, editor section, renderer) registered in one list; the switches iterate the list.

#### OCP-BASES-03 `default:` over the app's own enums hides new cases in 23 places of the evaluator
- **Severity:** Medium
- **Evidence:** grep `default:` in `BaseEvaluator.swift` gives 41 lines; by reading, 20 switch over `BaseValue` (222, 333, 373, 486, 524, 564, 579, 596, 612, 630, 710, 754, 768, 775, 791, 806, 823, 878, 1074, 1087), 3 over `BaseBinaryOperator` (233, 542, 639), 17 over function or member names, 1 over `Character`. Three `default:` branches stand for one specific case: `reduce` ([BaseEvaluator.swift:1116](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1116)), `>=` ([BaseEvaluator.swift:542](../../../Sources/GraphiteCore/BaseEvaluator.swift#L542)), `%` ([BaseEvaluator.swift:639](../../../Sources/GraphiteCore/BaseEvaluator.swift#L639)); `case .and, .or: return .boolean(false)` is unreachable ([BaseEvaluator.swift:547](../../../Sources/GraphiteCore/BaseEvaluator.swift#L547) after [BaseEvaluator.swift:226-232](../../../Sources/GraphiteCore/BaseEvaluator.swift#L226-L232)). Across the area the reconnaissance counts 101 `default:`.
- **Why it matters:** when `.html` was added to `BaseValue` ([BaseValue.swift:280](../../../Sources/GraphiteCore/BaseValue.swift#L280)) each of the 20 `BaseValue` switches had to be found by reading; the compiler flagged none. `BaseValue.==` shows the safe pattern (an exhaustive switch over the left value, [BaseValue.swift:343-376](../../../Sources/GraphiteCore/BaseValue.swift#L343-L376)).
- **Fix direction:** exhaustive switches over `BaseValue` and `BaseBinaryOperator`; name each operator case; remove the dead `.and, .or` arm by splitting short-circuit operators into their own enum.

#### OCP-BASES-04 Two hand-kept copies of the cross-type sort rank
- **Severity:** Low
- **Evidence:** `BaseValue.sortRank` ([BaseValue.swift:477-489](../../../Sources/GraphiteCore/BaseValue.swift#L477-L489)) and `BaseQueryEngine.sortingKind` with the literal `textSortingKind = 4` ([BaseQuery.swift:259-275](../../../Sources/GraphiteCore/BaseQuery.swift#L259-L275)); the comment says they must match ([BaseQuery.swift:261-262](../../../Sources/GraphiteCore/BaseQuery.swift#L261-L262)).
- **Why it matters:** a rank changed in one copy gives formula `sort()` and row sorting different orders, with no test pairing them.
- **Fix direction:** one `BaseValue.sortKind` enum (Comparable) used by both.

#### OCP-BASES-05 The value-type vocabulary sent to the plugin runtime is a second hand-kept list
- **Severity:** Low
- **Evidence:** `pluginValue` writes `"type"` strings per case ([CommunityPluginViews.swift:160-172](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L160-L172)) beside `BaseValue.typeName` ([BaseValue.swift:283-300](../../../Sources/GraphiteCore/BaseValue.swift#L283-L300)); the JavaScript side reads them in `community-plugin-runtime-bases.js` (named in the comment at line 159).
- **Why it matters:** the vocabulary is shared with JavaScript in three places with no generated source of truth.
- **Fix direction:** a `BaseValueWireType` enum in Core with a generated JavaScript constant table.

### L

#### LSP-BASES-01 The in-memory and index providers disagree on four rules, and Core tests pin the one production never uses
- **Severity:** High
- **Evidence:**

| Rule | In-memory | Index |
| --- | --- | --- |
| Rooted partial path `/Folder/Note` | Matches any path ending in `/Folder/Note.md` ([BaseFileRecord.swift:270-276](../../../Sources/GraphiteCore/BaseFileRecord.swift#L270-L276)) | Root only ([VaultIndex.swift:385-387](../../../Sources/GraphiteIndex/VaultIndex.swift#L385-L387)) |
| Target containing `:` | Looked up | Rejected ([VaultIndex.swift:378](../../../Sources/GraphiteIndex/VaultIndex.swift#L378)) |
| Backlinks from Markdown links | Resolved as Wikilinks, so aliases count ([BaseFileRecord.swift:284-288](../../../Sources/GraphiteCore/BaseFileRecord.swift#L284-L288)) | Resolved with the link's own kind; aliases name only Wikilinks ([VaultIndex.swift:481-494](../../../Sources/GraphiteIndex/VaultIndex.swift#L481-L494), [VaultIndex.swift:395-397](../../../Sources/GraphiteIndex/VaultIndex.swift#L395-L397)) |
| Case folding of names | Foundation `caseInsensitiveCompare` after composition ([BaseFileRecord.swift:267](../../../Sources/GraphiteCore/BaseFileRecord.swift#L267), [BaseFileRecord.swift:276](../../../Sources/GraphiteCore/BaseFileRecord.swift#L276)) | `lowercased()` then composition (`caseFoldedKey`, [MarkdownSemantics.swift:865-868](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L865-L868)); the index comment notes Foundation folds `straße` to `strasse` ([BaseRecordQueries.swift:55-58](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L55-L58)) |

  Production always passes the index provider ([BaseDocumentModel.swift:188](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L188)); the only other production construction is the silent default ([BaseEvaluator.swift:83](../../../Sources/GraphiteCore/BaseEvaluator.swift#L83)). By grep of `BaseEvaluator(formulas` and `BaseQueryEngine(` in `Tests/GraphiteCoreTests`, 21 call sites run without a provider (therefore in-memory) against 4 index-provider sites in `Tests/GraphiteIndexTests` and 1 in `Tests/GraphiteUITests`.
- **Why it matters:** link-related tests in Core (`file.links`, `hasLink`, `asFile`, `linksTo`, grouping by link, Unique) pass against rules production does not run; the comment claims "whose rules it follows" ([BaseFileRecord.swift:243-245](../../../Sources/GraphiteCore/BaseFileRecord.swift#L243-L245)).
- **Fix direction:** one `BaseRecordProviderContract` test suite run against both; move the in-memory provider to a test-support module and make it delegate name matching to the same pure resolver the index uses (`WikiLinkResolver` plus a folded-name table), or replace it with an index over a temporary database.

#### LSP-BASES-02 A failed index lookup is returned as "missing", and the failure travels in a side channel
- **Severity:** Medium
- **Evidence:** `read` records the error and returns nil ([BaseRecordQueries.swift:269-274](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L269-L274)); `record(at:)` and `backlinks` answer `nil` and `[]` ([BaseRecordQueries.swift:249-261](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L249-L261)); the evaluator caches the miss as a fact ([BaseEvaluator.swift:170-172](../../../Sources/GraphiteCore/BaseEvaluator.swift#L170-L172)); only `BaseDocumentModel` asks `throwIfLookupFailed()` ([BaseDocumentModel.swift:215](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L215)); the in-memory provider has no failure mode. Property rows that do not decode are skipped silently ([BaseRecordQueries.swift:213-215](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L213-L215)).
- **Why it matters:** any other consumer of `BaseRecordProvider` (tests, a future plugin bridge) computes values from missing data and never knows. `Docs/SOLID.md` lists this as open.
- **Fix direction:** make the protocol requirements `throws(BaseRecordLookupError)`; the evaluator turns a lookup error into a run failure, not a cell value.

#### LSP-BASES-03 The editor's setters do not round-trip keys the reader accepts under other names
- **Severity:** Medium
- **Evidence:** the reader takes `defaultZoom` or `zoom`, `mapHeight` or `height` ([BaseDefinition.swift:494-496](../../../Sources/GraphiteCore/BaseDefinition.swift#L494-L496)), `property` or `column` in sort keys ([BaseDefinition.swift:437](../../../Sources/GraphiteCore/BaseDefinition.swift#L437)), `groupBy` as a scalar ([BaseDefinition.swift:413](../../../Sources/GraphiteCore/BaseDefinition.swift#L413)), list markers under three spellings ([BaseDefinition.swift:462](../../../Sources/GraphiteCore/BaseDefinition.swift#L462)); `setOption` writes or removes only the key it is given ([BaseDefinitionEditor.swift:293-299](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L293-L299)) and the view editor passes `"defaultZoom"` ([BaseViewEditorSheet.swift:67](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L67)).
- **Why it matters:** "set to nil" does not store nil when the alias holds a value (BUG-BASES-01). The read-back check cannot catch it because it compares the edited tree, not the parsed definition ([BaseDefinitionEditor.swift:86-89](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L86-L89)).
- **Fix direction:** a `BaseViewOptionKey` registry (canonical key plus read aliases) shared by reader and editor; a setter writes the canonical key and removes every alias.

### I

#### ISP-BASES-01 Every Bases entry point takes the whole `VaultStore` and `VaultIndex` actors
- **Severity:** Medium
- **Evidence:** `BaseDocumentView`, `EmbeddedBaseView`, `BaseEmbedContext` and `BaseDocumentModel` take both ([BaseDocumentView.swift:26](../../../Sources/GraphiteUI/BaseDocumentView.swift#L26), [BaseDocumentView.swift:67](../../../Sources/GraphiteUI/BaseDocumentView.swift#L67), [BaseEmbedding.swift:8-9](../../../Sources/GraphiteUI/BaseEmbedding.swift#L8-L9), [BaseDocumentModel.swift:71](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L71)). Members used, counted by reading `BaseDocumentModel`: store `read` (103, 329, 522, 599), `save` (347, 529), `propertyTypes` (114), `root` (85, 442, 539): 4; index `baseRecord(at:)` (193), `baseRecords(matching:reusing:)` (204), `baseRecordProvider` (188), `resolve` (437), `refresh` (539): 5.
- **Why it matters:** a base can, by type, delete files, move vaults and rebuild the index; tests must build a real vault on disk; the read-only embedded case gets write capability.
- **Fix direction:** two capabilities owned by Bases: `BaseRecordSource` (the 4 index reads) and `BaseFileAccess` (read with revision, revision-checked save, property types); `refresh` moves behind `didSaveFile`.

#### ISP-BASES-02 The view mutates model state that should change only through intents
- **Severity:** Medium
- **Evidence:** `actionErrorMessage` is a settable `var` ([BaseDocumentModel.swift:36](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L36)) written by the view ([BaseDocumentView.swift:316](../../../Sources/GraphiteUI/BaseDocumentView.swift#L316), [BaseDocumentView.swift:458](../../../Sources/GraphiteUI/BaseDocumentView.swift#L458), [BaseDocumentView.swift:460](../../../Sources/GraphiteUI/BaseDocumentView.swift#L460)); `loadedContentVersion` is a settable `var` ([BaseDocumentModel.swift:67](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L67)) written by the view ([BaseDocumentView.swift:246](../../../Sources/GraphiteUI/BaseDocumentView.swift#L246)); `takeActionErrorMessage` reads and clears the shared field to carry a save failure into a sheet ([BaseDocumentView.swift:314-318](../../../Sources/GraphiteUI/BaseDocumentView.swift#L314-L318)).
- **Why it matters:** the outcome of `setProperty` and `editDefinition` reaches the sheet through a field, not a return value; the "reload only when content changed" rule lives half in the view.
- **Fix direction:** `setProperty` and `editDefinition` return `Result<…, BaseActionError>`; `reload(contentVersion:)` records the version itself; `actionErrorMessage` becomes `private(set)`.

#### ISP-BASES-03 `BaseViewActions` is a nine-member bag handed to every cell
- **Severity:** Low
- **Evidence:** [BaseValueViews.swift:12-26](../../../Sources/GraphiteUI/BaseValueViews.swift#L12-L26); a group header or summary needs none of `toggleCheckbox`, `beginEditing` or `thumbnails` yet receives them ([BaseCardsAndListViews.swift:162-176](../../../Sources/GraphiteUI/BaseCardsAndListViews.swift#L162-L176), [BaseTableView.swift:259-267](../../../Sources/GraphiteUI/BaseTableView.swift#L259-L267)).
- **Why it matters:** low cost today; any new cell capability widens every view's dependency.
- **Fix direction:** split into `BaseNavigationActions` (open path, open link), `BaseCellEditing` (edit request, begin, checkbox) and an environment value for the thumbnail store.

### D

#### DIP-BASES-01 The UI model performs file-system I/O and builds its own collaborators
- **Severity:** Medium
- **Evidence:** `FileManager.default.fileExists` on the main actor ([BaseDocumentModel.swift:441-445](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L441-L445)); `index.baseRecordProvider` built inside `runQuery` ([BaseDocumentModel.swift:188](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L188)); wall clock and device calendar read inline ([BaseDocumentModel.swift:185](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L185), [BaseDocumentModel.swift:195](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L195)); `index.refresh` called directly after a save ([BaseDocumentModel.swift:539](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L539)).
- **Why it matters:** link following bypasses `VaultStore`'s boundary and coordination; a provider-backed folder (iCloud) answers `fileExists` synchronously on the main thread; `now` is untestable.
- **Fix direction:** inject `BaseRecordSource`, `BaseFileAccess` and a clock; link following asks `BaseRecordSource.resolve`.

#### DIP-BASES-02 Core reads the device time zone behind the evaluation environment's back
- **Severity:** Medium
- **Evidence:** `displayCalendar` reads `TimeZone.current` ([BaseDateSupport.swift:234-238](../../../Sources/GraphiteCore/BaseDateSupport.swift#L234-L238)) and is used by `BaseValue.displayText` ([BaseValue.swift:410](../../../Sources/GraphiteCore/BaseValue.swift#L410)), `normalizedForSorting` ([BaseValue.swift:498](../../../Sources/GraphiteCore/BaseValue.swift#L498)), `orderedComparison` ([BaseValue.swift:553](../../../Sources/GraphiteCore/BaseValue.swift#L553), [BaseValue.swift:556](../../../Sources/GraphiteCore/BaseValue.swift#L556)), the summary default ([BaseQuery.swift:433](../../../Sources/GraphiteCore/BaseQuery.swift#L433)) and the environment default with `now: Date = .now` ([BaseEvaluator.swift:10](../../../Sources/GraphiteCore/BaseEvaluator.swift#L10)); meanwhile `format()`, `date()` and subtraction use `environment.calendar` ([BaseEvaluator.swift:607](../../../Sources/GraphiteCore/BaseEvaluator.swift#L607), [BaseEvaluator.swift:1135](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1135)).
- **Why it matters:** with an environment calendar in another zone (the evaluator test at [BaseEvaluatorTests.swift:256](../../../Tests/GraphiteCoreTests/BaseEvaluatorTests.swift#L256) builds one), `date.toString()` and `date.format("YYYY-MM-DD")` can name different days; tests depend on the machine's zone ([BaseEvaluatorTests.swift:24-34](../../../Tests/GraphiteCoreTests/BaseEvaluatorTests.swift#L24-L34)).
- **Fix direction:** `BaseValue.text(in calendar:)`, `normalizedForSorting(in:)` and `orderedComparison(_:_:in:)` take the calendar; remove the defaults so the composition root supplies clock and calendar once.

#### DIP-BASES-03 Omitting the provider silently changes semantics
- **Severity:** Medium
- **Evidence:** `provider: (any BaseRecordProvider)? = nil` defaults in `BaseEvaluator.init` ([BaseEvaluator.swift:78](../../../Sources/GraphiteCore/BaseEvaluator.swift#L78)), `BaseQueryEngine.init` ([BaseQuery.swift:118](../../../Sources/GraphiteCore/BaseQuery.swift#L118)) and `BaseRecordPrefilter.extract` ([BaseRecordPrefilter.swift:53](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L53)); nil becomes an in-memory provider over the batch only ([BaseEvaluator.swift:83](../../../Sources/GraphiteCore/BaseEvaluator.swift#L83)).
- **Why it matters:** a caller that forgets the argument gets backlinks limited to the batch and LSP-BASES-01's rules, with no compile error.
- **Fix direction:** make `provider` required; tests pass the contract-tested fake explicitly.

#### DIP-BASES-04 Cover and `image()` downloads use the shared URL session with cookies
- **Severity:** Medium
- **Evidence:** `URLSession.shared.bytes(from:)` ([BaseValueViews.swift:452](../../../Sources/GraphiteUI/BaseValueViews.swift#L452)) as the store's default decoder ([BaseValueViews.swift:437-444](../../../Sources/GraphiteUI/BaseValueViews.swift#L437-L444)); the tile path uses a hardened ephemeral session ([BaseTiledMapView.swift:31-38](../../../Sources/GraphiteUI/BaseTiledMapView.swift#L31-L38)). URLs come from note properties ([BaseQuery.swift:389-394](../../../Sources/GraphiteCore/BaseQuery.swift#L389-L394)).
- **Why it matters:** opening a base with web covers sends the shared cookie jar and fills the shared disk cache for any host a note names, which the tile path deliberately prevents; privacy differs by view type.
- **Fix direction:** one `BaseRemoteImageSession` (ephemeral, no cookies or credentials, memory cache only) injected into both the thumbnail store and the tile overlay.

### Clean code

#### CC-BASES-01 29 functions exceed 40 code lines
- **Severity:** Medium
- **Evidence:** reconnaissance list (appendix), confirmed by reading the largest: `callFunction` 109 ([BaseEvaluator.swift:716](../../../Sources/GraphiteCore/BaseEvaluator.swift#L716)), `YAMLSplicer.sequenceLines` 75 ([BaseDefinitionEditor.swift:1054](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L1054)), `BaseDateFormatting.text(for:fields:)` 63 ([BaseDateSupport.swift:299](../../../Sources/GraphiteCore/BaseDateSupport.swift#L299)), `BaseValueView.body` 62 ([BaseValueViews.swift:77](../../../Sources/GraphiteUI/BaseValueViews.swift#L77)), `runQuery` 62 ([BaseDocumentModel.swift:177](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L177)).
- **Why it matters:** `callFunction` and `runQuery` mix several jobs; the moment.js token switch is a table written as code.
- **Fix direction:** dispatch tables keyed by typed names; `runQuery` split into a pure run function plus publication; the token switch becomes a dictionary from token to field formatter.

#### CC-BASES-02 Ad-hoc "latest answer wins" and 17 owner-less view tasks
- **Severity:** Medium
- **Evidence:** two generation counters ([BaseDocumentModel.swift:58-61](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L58-L61)) checked at 116, 127, 226, 236, 239; `Task {}` in views: 14 in `BaseDocumentView.swift` (250, 282, 397, 430, 444, 455, 471, 476, 515, 534, 545, 559, 563, 566), 1 each at [BasePropertyEditorSheet.swift:111](../../../Sources/GraphiteUI/BasePropertyEditorSheet.swift#L111), [BaseTableView.swift:201](../../../Sources/GraphiteUI/BaseTableView.swift#L201), [BaseViewEditorSheet.swift:317](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L317) (grep `Task \{` over the area's UI files). A test waits on `Task.sleep(for: .milliseconds(20))` to order two reloads ([UiBasesDocumentModelTests.swift:189-190](../../../Tests/GraphiteUITests/UiBasesDocumentModelTests.swift#L189-L190)).
- **Why it matters:** each new async intent must remember to bump and check the right counter; tasks started from views outlive the view and nobody cancels them.
- **Fix direction:** one shared `LatestRequest` primitive for reload and query; UI events call synchronous model intents that own and cancel their tasks.

#### CC-BASES-03 Seven static regular expressions are built with `try?`
- **Severity:** Low
- **Evidence:** [BaseFileRecord.swift:145](../../../Sources/GraphiteCore/BaseFileRecord.swift#L145), [BaseFileRecord.swift:147](../../../Sources/GraphiteCore/BaseFileRecord.swift#L147), [BaseDateSupport.swift:8](../../../Sources/GraphiteCore/BaseDateSupport.swift#L8), [BaseDateSupport.swift:69-70](../../../Sources/GraphiteCore/BaseDateSupport.swift#L69-L70), [BaseQuery.swift:405](../../../Sources/GraphiteCore/BaseQuery.swift#L405), [BasePropertyEditing.swift:6](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L6) (grep `try\? NSRegularExpression`).
- **Why it matters:** a typo in a pattern makes every date or number silently text, which reads as "no dates in this vault" rather than a failure.
- **Fix direction:** a `CompiledPattern` helper that fails a unit test at load (one test touching every pattern), with no silent nil.

#### CC-BASES-04 The frontmatter regular expression exists four times, one copy byte-identical
- **Severity:** Low
- **Evidence:** [BasePropertyEditing.swift:6](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L6) equals [MarkdownSemantics.swift:29](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L29); variants at [MarkdownSemantics.swift:625](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L625) and [NoteProperties.swift:505](../../../Sources/GraphiteCore/NoteProperties.swift#L505) (grep `\\A---`).
- **Why it matters:** a base property edit and the note's own editor can disagree about where frontmatter ends.
- **Fix direction:** one `FrontmatterRange` function in Core used by all four.

#### CC-BASES-05 One concept, several rules: property-name matching and number reading
- **Severity:** Low
- **Evidence:** property names matched by `caseInsensitiveCompare` ([BaseFileRecord.swift:214-216](../../../Sources/GraphiteCore/BaseFileRecord.swift#L214-L216), [BaseValue.swift:234-237](../../../Sources/GraphiteCore/BaseValue.swift#L234-L237), [BaseEvaluator.swift:16-18](../../../Sources/GraphiteCore/BaseEvaluator.swift#L16-L18), [BasePropertyEditing.swift:23-24](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L23-L24), [BaseDocumentModel.swift:606-607](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L606-L607)) but by `folding(.caseInsensitive)` for editor kinds ([BaseDocumentModel.swift:494-496](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L494-L496)); numbers read by `Double(decimalText:)` ([BaseValue.swift:108](../../../Sources/GraphiteCore/BaseValue.swift#L108)), `javaScriptNumber` ([BaseEvaluator.swift:695](../../../Sources/GraphiteCore/BaseEvaluator.swift#L695)) and plain `Double(_:)` (accepts `nan`, `inf`, `0x1A`) in coordinates ([BaseQuery.swift:36](../../../Sources/GraphiteCore/BaseQuery.swift#L36), [BaseQuery.swift:46](../../../Sources/GraphiteCore/BaseQuery.swift#L46)), declared numbers ([BaseFileRecord.swift:125](../../../Sources/GraphiteCore/BaseFileRecord.swift#L125)) and view options ([BaseDefinition.swift:423](../../../Sources/GraphiteCore/BaseDefinition.swift#L423), [BaseDefinition.swift:447](../../../Sources/GraphiteCore/BaseDefinition.swift#L447)).
- **Why it matters:** six property lookups and five number rules; the comment at [BaseValue.swift:104-107](../../../Sources/GraphiteCore/BaseValue.swift#L104-L107) says hexadecimal is not a number, while coordinates accept it.
- **Fix direction:** `PropertyName` with one matching rule; `BaseNumberText` with named readers (`decimal`, `javaScript`) and the call sites choosing explicitly.

#### CC-BASES-06 Work and side effects in `body` and view initialisers
- **Severity:** Medium
- **Evidence:** `BaseHTMLValueView.body` parses up to 20,000 characters on every render ([BaseValueViews.swift:177-179](../../../Sources/GraphiteUI/BaseValueViews.swift#L177-L179)); `summaryText` parses again ([BaseValueViews.swift:162-163](../../../Sources/GraphiteUI/BaseValueViews.swift#L162-L163)); each Kanban card filters all groups and computes property values ([BaseKanbanView.swift:111](../../../Sources/GraphiteUI/BaseKanbanView.swift#L111)); `BaseContainerView.init` mutates `EmbeddedBaseModelCache` and may construct a model on every parent update ([BaseDocumentView.swift:213-218](../../../Sources/GraphiteUI/BaseDocumentView.swift#L213-L218)).
- **Why it matters:** a checkbox toggle in a table of `html()` cells re-parses every visible cell; the cache is reordered or refilled by SwiftUI's struct re-creation, so a model evicted while shown is rebuilt and cached without being displayed.
- **Fix direction:** `BaseQueryEngine` returns `BaseHTMLText` in the cell; Kanban move targets computed once per result; the cache lookup moves to `.task` or `onAppear`.

#### CC-BASES-07 User-visible English is produced in Core and carried as `String`
- **Severity:** Medium
- **Evidence:** `BaseDefinition.issues: [String]` filled with sentences ([BaseDefinition.swift:360](../../../Sources/GraphiteCore/BaseDefinition.swift#L360), [365](../../../Sources/GraphiteCore/BaseDefinition.swift#L365), [383](../../../Sources/GraphiteCore/BaseDefinition.swift#L383), [389](../../../Sources/GraphiteCore/BaseDefinition.swift#L389), [400](../../../Sources/GraphiteCore/BaseDefinition.swift#L400), [519](../../../Sources/GraphiteCore/BaseDefinition.swift#L519), [529](../../../Sources/GraphiteCore/BaseDefinition.swift#L529)); `BaseQueryResult.problems: [String]` ([BaseQuery.swift:103](../../../Sources/GraphiteCore/BaseQuery.swift#L103), sentences at 132, 153, 170, 182, 345); `BaseCellValue.error(String)` ([BaseQuery.swift:6](../../../Sources/GraphiteCore/BaseQuery.swift#L6)); `defaultDisplayName` wording ([BaseDefinition.swift:37-58](../../../Sources/GraphiteCore/BaseDefinition.swift#L37-L58)); about 40 `BaseExpressionError.evaluation("…")` sentences in the evaluator (grep `\.evaluation\("`).
- **Why it matters:** no string catalogue can translate them, tests assert on text, and callers cannot tell a syntax error from a timeout without parsing English.
- **Fix direction:** typed `BaseDefinitionIssue`, `BaseQueryProblem` and `BaseEvaluationError` cases with associated values; one presenter in UI turns them into words.

#### CC-BASES-08 A stale comment and comments narrating history
- **Severity:** Low
- **Evidence:** [BasePropertyEditing.swift:18](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L18) says `BaseFrontmatter` reads comment-only YAML as invalid; the code returns `[]` for it ([BaseFileRecord.swift:35-37](../../../Sources/GraphiteCore/BaseFileRecord.swift#L35-L37)). History phrasing: [BaseValue.swift:491-493](../../../Sources/GraphiteCore/BaseValue.swift#L491-L493) ("Without this, … sorted as text"), [BaseDateSupport.swift:230-231](../../../Sources/GraphiteCore/BaseDateSupport.swift#L230-L231) ("gave text in two languages"), [BaseEvaluator.swift:692-694](../../../Sources/GraphiteCore/BaseEvaluator.swift#L692-L694) ("where `Double(_:)` made them infinite"), [BaseExpression.swift:211](../../../Sources/GraphiteCore/BaseExpression.swift#L211) ("read as \"A\"").
- **Why it matters:** the stale comment justifies a fallback (`?? (properties.isEmpty ? [] : nil)`) that no longer guards anything; history belongs in commit messages.
- **Fix direction:** delete or rewrite as present-tense rules.

#### CC-BASES-09 Unnamed constants for sizes, clamps and durations
- **Severity:** Low
- **Evidence:** card size clamp 80…1,200 at parse ([BaseDefinition.swift:447](../../../Sources/GraphiteCore/BaseDefinition.swift#L447)) against a 120…600 stepper and default 220 in the editor ([BaseViewEditorSheet.swift:445-446](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L445-L446)); aspect ratio 0.1…10 ([BaseDefinition.swift:453-456](../../../Sources/GraphiteCore/BaseDefinition.swift#L453-L456)); zoom 0…24 and height 100…2,000 ([BaseDefinition.swift:492-496](../../../Sources/GraphiteCore/BaseDefinition.swift#L492-L496)); `365.2425` three times ([BaseDateSupport.swift:127](../../../Sources/GraphiteCore/BaseDateSupport.swift#L127), [BaseDateSupport.swift:399](../../../Sources/GraphiteCore/BaseDateSupport.swift#L399), [BaseEvaluator.swift:316](../../../Sources/GraphiteCore/BaseEvaluator.swift#L316)); `3_600_000` and `60_000` five times each across the two files; row heights 38/58/82/120 ([BaseTableView.swift:100-103](../../../Sources/GraphiteUI/BaseTableView.swift#L100-L103)); toolbar `+ 48` (named `BaseEmbeddedHeight.mapToolbarHeight` since 2026-10-19, [BaseEmbedding.swift](../../../Sources/GraphiteUI/BaseEmbedding.swift)).
- **Why it matters:** a card width written at 1,000 points parses but the stepper cannot show it; duplicated unit factors drift.
- **Fix direction:** `BaseDuration.millisecondsPerHour/Minute`, `averageDaysPerYear`; `BaseCardsOptions.cardSizeRange` shared by parser and editor; named layout tokens.

#### CC-BASES-10 Tests are named after audit rounds, and file names do not match their classes
- **Severity:** Low
- **Evidence:** `CoreBasesDatesFixTests`, `CoreBasesDefinitionQueryFixTests`, `CoreBasesEvaluatorFixTests`, `CoreBasesEdgeCaseFixTests`, `CoreBasesValuesFixTests`, `CoreAreaHandoffTests` (section 4 grep of `class \w*Base\w*Tests`); `BaseQueryTests.swift` declares `BaseDefinitionTests` ([BaseQueryTests.swift:4](../../../Tests/GraphiteCoreTests/BaseQueryTests.swift#L4)); `BaseEditingTests.swift` declares three classes ([BaseEditingTests.swift:4](../../../Tests/GraphiteCoreTests/BaseEditingTests.swift#L4), [180](../../../Tests/GraphiteCoreTests/BaseEditingTests.swift#L180), [222](../../../Tests/GraphiteCoreTests/BaseEditingTests.swift#L222)); `UiBasesRecordReuseTests` lives in `GraphiteIndexTests` ([UiBasesRecordReuseTests.swift:5](../../../Tests/GraphiteIndexTests/UiBasesRecordReuseTests.swift#L5)).
- **Why it matters:** finding the tests that pin `BaseEvaluator` means reading six files whose names say when they were written.
- **Fix direction:** rename to the production type pinned (`BaseEvaluatorTests`, `BaseDateArithmeticTests`, `BaseDefinitionReaderTests`, …), one class per file.

## 5. Defects and latent bugs

#### BUG-BASES-01 Turning off "Default Zoom" does nothing on a map written with `zoom:`
- **Trigger:** a map view written as `zoom: 12` (an alias the reader accepts because published bases use it); the user opens Edit View, turns "Default Zoom" off and saves.
- **Path:** the reader takes `defaultZoom ?? zoom` ([BaseDefinition.swift:495](../../../Sources/GraphiteCore/BaseDefinition.swift#L495)) → the draft starts at 12 ([BaseViewEditorSheet.swift:44](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L44)) → the toggle sets nil ([BaseViewEditorSheet.swift:465](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L465)) → `apply` calls `setOption("defaultZoom", number: nil)` ([BaseViewEditorSheet.swift:67](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L67)) → the editor removes only the absent `defaultZoom` key ([BaseDefinitionEditor.swift:297-299](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L297-L299)) → the edited tree means what the original meant, so `yaml()` returns the original text ([BaseDefinitionEditor.swift:66](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L66)) → the identical bytes are saved and the sheet closes as a success ([BaseDocumentModel.swift:347-351](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L347-L351), [BaseViewEditorSheet.swift:318-323](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L318-L323)) → the reload reads `zoom: 12` again.
- **Effect:** the edit reports success and the map keeps its fixed zoom; the user cannot clear it from Graphite.
- **Platforms / reach:** iPad, iPhone, Mac; normal path for any base using `zoom`. The same mechanism applies to any future option edited under one of several read names (LSP-BASES-03).
- **Confidence:** Traced.

#### BUG-BASES-02 Markdown links in a note's body resolve through other notes' aliases in filters and formulas
- **Trigger:** `Notes/A.md` contains `[see](Bob)`; `People/Robert.md` has `aliases: [Bob]`; no file is named Bob. A base filters `file.hasLink(file("People/Robert.md"))`, or a formula reads `file.links` and calls `asFile()`.
- **Path:** the index stores the Markdown target as written, `Bob`, with `isWiki` false ([VaultIndex.swift:510-520](../../../Sources/GraphiteIndex/VaultIndex.swift#L510-L520)) → records keep `isWiki` ([BaseRecordQueries.swift:221-222](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L221-L222)) → `hasLink` collects targets as bare strings, dropping the kind ([BaseEvaluator.swift:1168-1172](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1168-L1172), [BaseEvaluator.swift:438-442](../../../Sources/GraphiteCore/BaseEvaluator.swift#L438-L442)) → `link(_:from:pointsTo:)` calls `resolveLink` ([BaseEvaluator.swift:460-461](../../../Sources/GraphiteCore/BaseEvaluator.swift#L460-L461), [BaseEvaluator.swift:157](../../../Sources/GraphiteCore/BaseEvaluator.swift#L157)) → the index provider always passes `isWiki: true` ([BaseRecordQueries.swift:253-254](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L253-L254)) → the Wikilink branch matches the alias ([VaultIndex.swift:392-394](../../../Sources/GraphiteIndex/VaultIndex.swift#L392-L394)) → `true`. The same note's backlinks are resolved with the stored kind, where "a Markdown link names a file" ([VaultIndex.swift:481-494](../../../Sources/GraphiteIndex/VaultIndex.swift#L481-L494), [VaultIndex.swift:395-397](../../../Sources/GraphiteIndex/VaultIndex.swift#L395-L397)), so `file("People/Robert.md").backlinks` excludes `A.md`.
- **Effect:** the base lists `A.md` as linking to Robert while Robert's backlinks (in the same base and in the backlinks panel) do not; `link.asFile()` opens Robert for a link Obsidian leaves unresolved.
- **Platforms / reach:** iPad, iPhone, Mac; normal path for vaults that use Markdown links and aliases.
- **Confidence:** Traced.

#### BUG-BASES-03 `file.hasLink(file("Name"))` silently drops rows when a note of that name sits at the vault root
- **Trigger:** `Note.md` at the root and `A/Note.md`; `A/X.md` writes `[[A/Note]]`; a base filters `file.hasLink(file("Note"))`.
- **Path (evaluator keeps the row):** `file("Note")` resolves from the row's folder ([BaseEvaluator.swift:796-799](../../../Sources/GraphiteCore/BaseEvaluator.swift#L796-L799), [BaseEvaluator.swift:480-485](../../../Sources/GraphiteCore/BaseEvaluator.swift#L480-L485)) → beside the note first ([MarkdownSemantics.swift:898-900](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L898-L900)) → `A/Note.md`; `[[A/Note]]` from `A/X.md` resolves to `A/Note.md` → `hasLink` is true.
- **Path (prefilter excludes it):** `dependsOnCurrentRow` is false for a function call with literal arguments ([BaseExpression.swift:493](../../../Sources/GraphiteCore/BaseExpression.swift#L493)) → `constantValue` evaluates `file("Note")` with no record ([BaseRecordPrefilter.swift:100](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L100)) → resolution from the root gives `Note.md` ([BaseEvaluator.swift:156-161](../../../Sources/GraphiteCore/BaseEvaluator.swift#L156-L161)) → requirement `.linksTo(.path(Note.md))` ([BaseRecordPrefilter.swift:120](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L120)) → the SQL accepts only targets `note.md`, `/note.md`, `note`, `/note`, aliases, relative endings or padded forms ([BaseRecordQueries.swift:143-147](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L143-L147), [BaseRecordQueries.swift:166-169](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L166-L169), [BaseRecordQueries.swift:179-187](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L179-L187)) → the stored target `a/note` matches none → `A/X.md` is never loaded.
- **Effect:** a matching note is missing from the base with no problem shown; this breaks the prefilter's stated superset contract ([BaseRecordPrefilter.swift:38-40](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L38-L40)).
- **Platforms / reach:** iPad, iPhone, Mac; vaults with duplicate note names (common: `README`, `Index`, daily-note names in several folders).
- **Confidence:** Traced.

#### BUG-BASES-04 Tapping a link cell can open a different note than the one the base resolves
- **Trigger:** `Folder/A.md` has `related: "[[Sub/Note.md]]"`; both `Sub/Note.md` and `Folder/Sub/Note.md` exist; the user taps the link in a table cell.
- **Path:** the cell holds a link whose source is `Folder/A.md` ([BaseFileRecord.swift:119-120](../../../Sources/GraphiteCore/BaseFileRecord.swift#L119-L120)) → the button calls `openLink` ([BaseValueViews.swift:113](../../../Sources/GraphiteUI/BaseValueViews.swift#L113), [BaseDocumentView.swift:454-457](../../../Sources/GraphiteUI/BaseDocumentView.swift#L454-L457)) → `resolve` checks the written path as a vault-root file on disk first and returns `Sub/Note.md` ([BaseDocumentModel.swift:435-436](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L435-L436)). The base itself resolves the same link beside the note first ([VaultIndex.swift:366-375](../../../Sources/GraphiteIndex/VaultIndex.swift#L366-L375)) when grouping ([BaseQuery.swift:321](../../../Sources/GraphiteCore/BaseQuery.swift#L321)) or for `related.asFile()` ([BaseEvaluator.swift:1185-1186](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1185-L1186)), giving `Folder/Sub/Note.md`.
- **Effect:** the user opens the wrong note; a group header and the tapped link disagree.
- **Platforms / reach:** iPad, iPhone, Mac; links written with an extension and a folder, with duplicate relative and root paths.
- **Confidence:** Traced.

#### BUG-BASES-05 Editing a view of a base whose `views` come from a root merge key hides those views
- **Trigger:** a `.base` whose root mapping takes `views` through `<<: *defaults`; the user edits the first view (for example a header sort saved to the view, or a column width).
- **Path:** the reader applies merge keys ([BaseDefinition.swift:289](../../../Sources/GraphiteCore/BaseDefinition.swift#L289), [BaseDefinition.swift:307-329](../../../Sources/GraphiteCore/BaseDefinition.swift#L307-L329)) and shows the merged views → the editor reads the raw root mapping ([BaseDefinitionEditor.swift:322](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L322)), finds no `views`, and substitutes one default table ([BaseDefinitionEditor.swift:333-336](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L333-L336)) → `updateView(at: 0)` writes `views:` with that single table ([BaseDefinitionEditor.swift:341-347](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L341-L347)) → the read-back compares against the edited raw tree, which matches ([BaseDefinitionEditor.swift:79](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L79)) → saved. An explicit key wins over merged ones on the next read ([BaseDefinition.swift:318-324](../../../Sources/GraphiteCore/BaseDefinition.swift#L318-L324)). Editing view 2 or later is refused instead ([BaseDefinitionEditor.swift:343](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L343)).
- **Effect:** after one edit the base shows a single "Table" view; the merged views stay in the file under their anchor but no longer appear.
- **Platforms / reach:** iPad, iPhone, Mac; only bases that use a root-level merge key (rare, hand-written).
- **Confidence:** Partly traced: Yams is not in the snapshot, so whether `Yams.compose` leaves `<<` unresolved could not be read; the reader's explicit merge pass ([BaseDefinition.swift:305-329](../../../Sources/GraphiteCore/BaseDefinition.swift#L305-L329)) and the view-level merge tests ([CoreBasesDefinitionQueryFixTests.swift:184-190](../../../Tests/GraphiteCoreTests/CoreBasesDefinitionQueryFixTests.swift#L184-L190)) only make sense if it does.

## 6. What to keep

| Sound design | Evidence | Why it is sound |
| --- | --- | --- |
| Prefilter as a superset with an ASCII escape hatch | [BaseRecordPrefilter.swift:38-40](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L38-L40), [BaseRecordQueries.swift:53-67](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L53-L67), [BaseRecordQueries.swift:76](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L76), [BaseRecordQueries.swift:99-106](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L99-L106) | Only conjunctions narrow; `or` and `not` add nothing; non-ASCII input skips narrowing and non-ASCII stored text always passes, so SQLite's ASCII folding cannot drop a row. A test pins that equal values contain the text in stored JSON ([CoreBasesDefinitionQueryEngineTests.swift:198-209](../../../Tests/GraphiteCoreTests/CoreBasesDefinitionQueryEngineTests.swift#L198-L209)). |
| Fail-closed filters | [BaseDefinition.swift:350-354](../../../Sources/GraphiteCore/BaseDefinition.swift#L350-L354), [BaseDefinition.swift:402-406](../../../Sources/GraphiteCore/BaseDefinition.swift#L402-L406), [BaseQuery.swift:130-139](../../../Sources/GraphiteCore/BaseQuery.swift#L130-L139), [BaseDocumentModel.swift:197-201](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L197-L201) | A filter that is not fully read never widens a view; a parse error anywhere blocks the run. |
| YAML-preserving edit with read-back | [BaseDefinitionEditor.swift:60-110](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L60-L110), [BaseDefinitionEditor.swift:563-577](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L563-L577) | Unchanged returns the original bytes; splices only changed entries; compares meaning including custom tags; refuses rather than strips. |
| Supplementary-plane placeholder trick for libyaml | [BaseDefinitionEditor.swift:126-146](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L126-L146) | Keeps emoji literal in rewritten lines without `\U` escapes. |
| Revision-checked saves, view targets, BOM | [BaseDocumentModel.swift:329-347](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L329-L347), [BaseDocumentModel.swift:615-629](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L615-L629), [BaseDocumentModel.swift:634-648](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L634-L648) | Another app's edit is never overwritten; an edit prepared on one view never lands on another; a byte order mark survives. |
| Checked property rewrite | [BasePropertyEditing.swift:29-46](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L29-L46), [BasePropertyEditing.swift:75-102](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L75-L102) | Compares untouched properties as YAML nodes, refuses nested values, verifies the new value reads back. |
| Draft-versus-file state in the view editor | [BaseViewEditorSheet.swift:113-165](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L113-L165) | A typed `FileChange` instead of booleans; a stale draft cannot be saved over a changed view. |
| Stack guards | [BaseExpression.swift:281-341](../../../Sources/GraphiteCore/BaseExpression.swift#L281-L341), [BaseEvaluator.swift:185-189](../../../Sources/GraphiteCore/BaseEvaluator.swift#L185-L189), [BaseEvaluator.swift:241-253](../../../Sources/GraphiteCore/BaseEvaluator.swift#L241-L253) | A hostile `.base` becomes a cell error, not a crash on a 512 KiB thread. |
| Value equality and hashing | [BaseValue.swift:78-102](../../../Sources/GraphiteCore/BaseValue.swift#L78-L102), [BaseValue.swift:341-398](../../../Sources/GraphiteCore/BaseValue.swift#L341-L398) | Reflexive with NaN; the exhaustive left-value switch makes a new case a compile error; formula `==` stays separate and documented ([BaseValue.swift:336-340](../../../Sources/GraphiteCore/BaseValue.swift#L336-L340)). |
| Overflow-safe durations | [BaseValue.swift:42-75](../../../Sources/GraphiteCore/BaseValue.swift#L42-L75), [BaseDateSupport.swift:418-446](../../../Sources/GraphiteCore/BaseDateSupport.swift#L418-L446) | Formula input like `duration("999999999y") * 999999999` never traps. |
| JavaScript-compatible text and numbers | [BaseValue.swift:426-470](../../../Sources/GraphiteCore/BaseValue.swift#L426-L470), [BaseEvaluator.swift:658-701](../../../Sources/GraphiteCore/BaseEvaluator.swift#L658-L701), [BaseEvaluator.swift:953-974](../../../Sources/GraphiteCore/BaseEvaluator.swift#L953-L974), [BaseEvaluator.swift:1229-1334](../../../Sources/GraphiteCore/BaseEvaluator.swift#L1229-L1334) | Number printing, `toFixed`, `split` and `replace` match Obsidian's JavaScript; UTF-16 `length` and `slice` ([BaseEvaluator.swift:327-328](../../../Sources/GraphiteCore/BaseEvaluator.swift#L327-L328), [BaseEvaluator.swift:915-919](../../../Sources/GraphiteCore/BaseEvaluator.swift#L915-L919)). |
| Wall-clock date arithmetic and moment formatting | [BaseDateSupport.swift:163-222](../../../Sources/GraphiteCore/BaseDateSupport.swift#L163-L222), [BaseDateSupport.swift:232-297](../../../Sources/GraphiteCore/BaseDateSupport.swift#L232-L297), [BaseDateSupport.swift:452-501](../../../Sources/GraphiteCore/BaseDateSupport.swift#L452-L501) | Daylight-saving and month overflow as JavaScript; English text regardless of device locale; lazily computed fields. |
| Regular expression time limit | [BaseEvaluator.swift:976-987](../../../Sources/GraphiteCore/BaseEvaluator.swift#L976-L987), [BaseEvaluator.swift:883-890](../../../Sources/GraphiteCore/BaseEvaluator.swift#L883-L890) | Catastrophic patterns become a cell error; compiled once per run. |
| Folder-keyed link memo | [BaseEvaluator.swift:146-165](../../../Sources/GraphiteCore/BaseEvaluator.swift#L146-L165), [BaseFileRecord.swift:236-239](../../../Sources/GraphiteCore/BaseFileRecord.swift#L236-L239) | One resolution per folder instead of per row, with the contract stated on the protocol. |
| Record reuse by row revision | [BaseRecordReuse.swift:5-17](../../../Sources/GraphiteIndex/BaseRecordReuse.swift#L5-L17), [BaseRecordReuse.swift:58-81](../../../Sources/GraphiteIndex/BaseRecordReuse.swift#L58-L81) | The invariant is written beside the code; only changed files are re-read. |
| Bounded loading | [BaseRecordQueries.swift:10-17](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L10-L17), [BaseRecordQueries.swift:22-34](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L22-L34) | 5,000 records by default, 20,000 maximum, truncation reported ([BaseDocumentView.swift:377-380](../../../Sources/GraphiteUI/BaseDocumentView.swift#L377-L380)). |
| Fast scalar decode with fallback | [BaseRecordQueries.swift:292-337](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L292-L337) | Handles the common case without `JSONDecoder` and falls back on anything unusual. |
| Lookup failure surfaced before publishing | [BaseRecordQueries.swift:277-289](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L277-L289), [BaseDocumentModel.swift:212-215](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L212-L215) | Rows computed from a failed read are never shown (keep the behaviour; move it into the contract per LSP-BASES-02). |
| Hardened tile fetching and scheme filtering | [BaseTiledMapView.swift:13-65](../../../Sources/GraphiteUI/BaseTiledMapView.swift#L13-L65), [BaseMapTiles.swift:47-54](../../../Sources/GraphiteCore/BaseMapTiles.swift#L47-L54), [BaseMapTiles.swift:76](../../../Sources/GraphiteCore/BaseMapTiles.swift#L76), [BaseQuery.swift:407-412](../../../Sources/GraphiteCore/BaseQuery.swift#L407-L412) | No cookies, credentials or disk cache; http(s) only; 4 MB cap; covers never load `file://`. The `@unchecked Sendable` handler states its invariant ([BaseTiledMapView.swift:68-74](../../../Sources/GraphiteUI/BaseTiledMapView.swift#L68-L74)). |
| Inert `html()` | [BaseHTMLText.swift:1-58](../../../Sources/GraphiteCore/BaseHTMLText.swift#L1-L58), [BaseHTMLText.swift:64-82](../../../Sources/GraphiteCore/BaseHTMLText.swift#L64-L82), [BaseHTMLText.swift:407-413](../../../Sources/GraphiteCore/BaseHTMLText.swift#L407-L413) | Native text from untrusted markup; nothing runs or loads; bounded size and depth. |
| Thumbnail store | [BaseValueViews.swift:397-526](../../../Sources/GraphiteUI/BaseValueViews.swift#L397-L526) | Actor-owned budget, one decode per location, file-version invalidation, injectable decoder. |
| Result de-duplication before publishing | [BaseDocumentModel.swift:228-229](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L228-L229), [BaseDocumentModel.swift:253-257](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L253-L257) | An index change after every autosave does not re-lay out every row. |
| Pure helpers already extracted as statics | `sortOverride(afterTappingHeaderOf:…)` ([BaseDocumentModel.swift:291-298](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L291-L298)), `propertyValue(forGroupKey:)` ([BaseDocumentModel.swift:571-592](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L571-L592)), `BaseColumnResize` ([BaseTableView.swift:296-323](../../../Sources/GraphiteUI/BaseTableView.swift#L296-L323)), `BaseMapView.region`/`centerCoordinate` ([BaseMapView.swift:186-210](../../../Sources/GraphiteUI/BaseMapView.swift#L186-L210)) | Decide-then-do already in place; unit-tested without UI. |

## 7. Blueprint for this area

### Target shape

| Type (module) | Single responsibility | Seam |
| --- | --- | --- |
| `BaseDefinition` + `BaseDefinitionReader` (Core) | `.base` model and reading | none |
| `BaseViewOptionKey` (Core) | Canonical key and read aliases for each view option | shared by reader and editor |
| `BaseDefinitionEditor` (Core) | View operations on the YAML tree; every mutator throws | none |
| `YAMLPreservingWriter` group (Core): `YAMLSourceLine`, `WrittenYAMLNode`, `RewrittenYAMLWriter`, `YAMLSplicer` | Write a changed YAML tree keeping untouched text | none |
| `BaseExpression` + parser (Core) | Syntax | none |
| `BaseFunctionName`, `BaseMethodName` (Core) | The typed expression vocabulary, with arity and null-receiver result | consumed by evaluator and prefilter |
| `BaseEvaluator` (Core) | Interpreter: walk, scope, depth guard | none |
| `BaseRecordLookup` (Core) | Per-run memo and the only link-identity owner (kind-aware) | uses `BaseRecordProvider` |
| `BaseRecordProvider` (Core protocol, throwing, kind-aware) | Records, link resolution, backlinks | **real seam**: index in production, contract-tested fake in tests |
| `BaseValueOperators`, function and method libraries, `JavaScriptText` (Core) | Value semantics | none |
| `BaseRecordPrefilter` (Core) | Superset extraction, sharing the vocabulary enums and a correct `dependsOnCurrentRow` | none |
| `BaseQueryEngine`, `BaseSummaryCalculator`, `BaseCoordinate`, `BaseQueryResult` (Core, one file each) | Filter, sort, group, cells (including typed `BaseImageReference` and parsed `BaseHTMLText`) | none |
| `BaseIndexRecordProvider` (Index) | SQL-backed provider | implements the protocol |
| `BaseRecordSource` (UI-owned capability) | `baseRecord(at:)`, `baseRecords(matching:reusing:)`, `makeProvider()`, `resolve` | **real seam**: tests without a database |
| `BaseFileAccess` (UI-owned capability) | Read with revision, revision-checked save, property types | **real seam**: refusal and conflict tests |
| `BaseDefinitionFile`, `BaseViewSelection`, `BaseQueryRun`, `BaseNotePropertyWriter` (UI) | Section 3.2 split | none |
| `BaseDocumentModel` (UI) | Observable state and intents | none |
| `BaseViewKind` descriptors (UI, one per supported type) | Name, symbol, editor section, renderer | registered in one list |
| `BaseRemoteImageSession` (UI) | Hardened session for covers and tiles | injected |

Protocols are added only where a second implementation exists or a test needs isolation: `BaseRecordProvider` (already two implementations), `BaseRecordSource` and `BaseFileAccess` (tests today need a real vault and SQLite). No other protocols.

### Ordered steps (each leaves the app building and behaving the same, except where a step fixes a bug)

1. **Pin current behaviour.** Add `BaseRecordProviderContractTests` running one fixture vault against both providers; mark the four LSP-BASES-01 differences as expected failures. Add regression tests for BUG-BASES-01 to -05.
2. **Make the provider required.** Remove the `nil` default in `BaseEvaluator`, `BaseQueryEngine` and `BaseRecordPrefilter.extract`; tests pass a provider explicitly. No behaviour change in production.
3. **Align the in-memory provider with the index** (or replace it with an index over a temporary database) until the contract suite passes; move it to a test-support target.
4. **Carry the link kind.** Add `kind` (wiki, markdown) to `BaseLink` and to `BaseRecordProvider.resolveLinkTarget`; `linkTargets` keeps `BaseRecordLink`. Fixes BUG-BASES-02.
5. **One link owner.** Extract `BaseRecordLookup`; route `BaseDocumentModel.resolve` through `BaseRecordSource.resolve` and delete the `FileManager` check. Fixes BUG-BASES-04.
6. **Fix row dependence.** `dependsOnCurrentRow` returns true for `file(…)`, `link(…)` and string arguments that name files; the prefilter maps such `hasLink` arguments to `.target`. Fixes BUG-BASES-03.
7. **Option keys.** Introduce `BaseViewOptionKey`; setters write the canonical key and remove aliases. Fixes BUG-BASES-01. Apply merge keys in the editor's view lookup, or refuse edits when `views` arrives through a merge key. Fixes BUG-BASES-05.
8. **Throwing provider.** Make the protocol throw a typed lookup error; remove `throwIfLookupFailed()` once the evaluator propagates errors.
9. **Split `BaseEvaluator`** into the files in section 3.1 with no behaviour change; then replace string dispatch with `BaseFunctionName`/`BaseMethodName` and make every switch over `BaseValue` and `BaseBinaryOperator` exhaustive.
10. **Clock and calendar.** Remove `Date.now`/`displayCalendar` defaults; thread `environment.calendar` into `displayText`, `normalizedForSorting` and `orderedComparison`.
11. **Split `BaseDocumentModel`** per section 3.2 behind `BaseRecordSource` and `BaseFileAccess`; replace both generation counters with a shared latest-request primitive; intents return typed outcomes; `actionErrorMessage` becomes `private(set)`.
12. **Typed problems.** Replace `issues`, `problems`, `BaseCellValue.error(String)` and evaluation messages with typed cases and one presenter.
13. **View kinds and remote images.** Register `BaseViewKind` descriptors; inject `BaseRemoteImageSession` into the thumbnail store.
14. **Move the YAML writer** into its own files; `addView` throws.
15. **Rename tests** after the production types they pin.

### Behaviour that must be preserved

| ID | Invariant | Test idea |
| --- | --- | --- |
| BASES-INV-01 | Saving an unedited definition returns the original text byte for byte ([BaseDefinitionEditor.swift:66](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L66)). | Golden corpus of `.base` files with comments, CRLF, tags, anchors: `yaml()` equals input. |
| BASES-INV-02 | An edit rewrites only the changed entries' lines; new lines use the file's predominant line ending, ties to LF ([BaseDefinitionEditor.swift:112-121](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L112-L121)). | Line diff of before/after has only the edited key's lines. |
| BASES-INV-03 | An output that does not read back as the edited tree is refused with nothing saved ([BaseDefinitionEditor.swift:79-81](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L79-L81)). | A tag with unwritable characters throws; file bytes unchanged. |
| BASES-INV-04 | Column widths are written as whole points under the property's full spelling (`note.x`, `file.x`, `formula.x`), clamped 40…2,000; zero and non-numbers are ignored on read ([BaseDefinitionEditor.swift:276-290](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L276-L290), [BaseDefinition.swift:419-425](../../../Sources/GraphiteCore/BaseDefinition.swift#L419-L425)). | Round-trip `columnSize` with `status` and `note.status` spellings. |
| BASES-INV-05 | Property identifiers: `note.`, `file.`, `formula.` prefixes; a bare name is a note property; written back with the prefix ([BaseDefinition.swift:13-28](../../../Sources/GraphiteCore/BaseDefinition.swift#L13-L28)); existing order entries keep their spelling ([BaseDefinitionEditor.swift:232-243](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L232-L243)). | Reorder a view written with bare names: bare spellings remain. |
| BASES-INV-06 | `BaseView.id` is the position in the file's `views` list, counting entries that are not mappings; the editor addresses views by that position ([BaseDefinition.swift:381-386](../../../Sources/GraphiteCore/BaseDefinition.swift#L381-L386), [BaseDocumentModel.swift:358-366](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L358-L366)). | A `views` list with a scalar first: editing the second view edits file entry 2. |
| BASES-INV-07 | Null values are absent keys; merge keys apply, own keys first, then earlier merges ([BaseDefinition.swift:298-329](../../../Sources/GraphiteCore/BaseDefinition.swift#L298-L329)). | `<<: [*a, *b]` with conflicting keys. |
| BASES-INV-08 | A base with no views shows one table named "Table" ([BaseDefinition.swift:337-342](../../../Sources/GraphiteCore/BaseDefinition.swift#L337-L342)). | Empty file and `~` both give one view. |
| BASES-INV-09 | Unreadable global or view filters load zero records and report a problem ([BaseQuery.swift:130-133](../../../Sources/GraphiteCore/BaseQuery.swift#L130-L133), [BaseDocumentModel.swift:197-201](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L197-L201)). | Existing `testUnreadableFiltersShowAProblemWithoutLoadingVaultRecords`. |
| BASES-INV-10 | The prefilter never excludes a record the evaluator would keep ([BaseRecordPrefilter.swift:38-40](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L38-L40)). Currently violated by BUG-BASES-03. | Property test: random small vaults and filters; rows(prefiltered) ⊇ rows(all records). |
| BASES-INV-11 | A provider's link answer depends on the source only through its folder ([BaseFileRecord.swift:236-239](../../../Sources/GraphiteCore/BaseFileRecord.swift#L236-L239)). | Contract test: two sources in one folder give equal answers for every target. |
| BASES-INV-12 | Sorting puts empty values and errors last in both directions; ties fall back to natural file-name order, then path ([BaseQuery.swift:207-256](../../../Sources/GraphiteCore/BaseQuery.swift#L207-L256)). | Descending sort with nulls stays nulls-last. |
| BASES-INV-13 | Grouping: links group by resolved file, `null`, `""` and `[]` share one "empty" group, groups sort like rows ([BaseQuery.swift:279-329](../../../Sources/GraphiteCore/BaseQuery.swift#L279-L329)). | `[[Ann]]` and `[[People/Ann]]` in one group. |
| BASES-INV-14 | Numbers print as JavaScript's `String(number)` ([BaseValue.swift:426-470](../../../Sources/GraphiteCore/BaseValue.swift#L426-L470)). | `1e21`, `1e-7`, `0.000001`, `-0`. |
| BASES-INV-15 | Date `toString()` is `YYYY-MM-DD` or `YYYY-MM-DDTHH:mm:ss` ([BaseDateSupport.swift:242-244](../../../Sources/GraphiteCore/BaseDateSupport.swift#L242-L244)); formatting is moment's English whatever the device locale ([BaseDateSupport.swift:228-231](../../../Sources/GraphiteCore/BaseDateSupport.swift#L228-L231)). | German device locale gives English month names. |
| BASES-INV-16 | Text `length`, `slice` and subscript count UTF-16 units ([BaseEvaluator.swift:327-328](../../../Sources/GraphiteCore/BaseEvaluator.swift#L327-L328), [BaseEvaluator.swift:365-368](../../../Sources/GraphiteCore/BaseEvaluator.swift#L365-L368), [BaseEvaluator.swift:915-919](../../../Sources/GraphiteCore/BaseEvaluator.swift#L915-L919)). | Existing `testTextLengthAndSliceCountUTF16Units`. |
| BASES-INV-17 | Durations keep months and days apart; a month converts with 146,097/4,800 days; years fold to 12 months ([BaseValue.swift:15-27](../../../Sources/GraphiteCore/BaseValue.swift#L15-L27)). | `date + "1M"` from January 31 gives March 3 in 2025. |
| BASES-INV-18 | Date arithmetic moves the local wall clock; a skipped time moves forward, a repeated time takes its first occurrence ([BaseDateSupport.swift:163-222](../../../Sources/GraphiteCore/BaseDateSupport.swift#L163-L222)). | `+ "24h"` across a DST change keeps the clock time. |
| BASES-INV-19 | `===` and `!==` mean `==` and `!=`, which compare numbers and dates with their text by value ([BaseExpression.swift:140-143](../../../Sources/GraphiteCore/BaseExpression.swift#L140-L143), [BaseEvaluator.swift:522-523](../../../Sources/GraphiteCore/BaseEvaluator.swift#L522-L523)). | `1 === "1"` is true. |
| BASES-INV-20 | `BaseValue.==` is reflexive for NaN and distinguishes cases with equal text ([BaseValue.swift:341-398](../../../Sources/GraphiteCore/BaseValue.swift#L341-L398)); formula `==` keeps NaN ≠ NaN ([BaseEvaluator.swift:498](../../../Sources/GraphiteCore/BaseEvaluator.swift#L498)). | Set of `[.number(.nan), .number(.nan)]` has one element. |
| BASES-INV-21 | A note or `.base` save keeps a leading UTF-8 byte order mark ([BaseDocumentModel.swift:634-648](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L634-L648)). | Existing BOM tests in `UiBasesDocumentModelTests`. |
| BASES-INV-22 | Every save is revision-checked against the snapshot read for it; a `.base` edit also requires the revision the shown definition came from ([BaseDocumentModel.swift:330](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L330), [BaseDocumentModel.swift:347](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L347), [BaseDocumentModel.swift:529](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L529)). | Change the file between read and save through a `BaseFileAccess` fake: refused. |
| BASES-INV-23 | Property edits refuse: nested mappings, lists of non-scalars, changes to any other property's YAML node, values that do not read back ([BasePropertyEditing.swift:29-36](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L29-L36), [BasePropertyEditing.swift:75-102](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L75-L102)). | Value `a # b` on a text property is refused. |
| BASES-INV-24 | Size limits: `.base` ≤ 1 MiB ([BaseDefinition.swift:246](../../../Sources/GraphiteCore/BaseDefinition.swift#L246)); edited notes ≤ 8 MiB ([BaseDocumentModel.swift:19](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L19)); records 5,000 default and 20,000 maximum, 500 paths per statement, 32 link destinations ([BaseRecordQueries.swift:10-17](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L10-L17)); `html()` 20,000 characters and depth 64 ([BaseHTMLText.swift:44-46](../../../Sources/GraphiteCore/BaseHTMLText.swift#L44-L46)). | Boundary tests at each limit. |
| BASES-INV-25 | Parser depth 64 and stack cost 100; evaluator checks headroom (128 KiB) beyond depth 16 ([BaseExpression.swift:288](../../../Sources/GraphiteCore/BaseExpression.swift#L288), [BaseExpression.swift:294](../../../Sources/GraphiteCore/BaseExpression.swift#L294), [BaseEvaluator.swift:52-56](../../../Sources/GraphiteCore/BaseEvaluator.swift#L52-L56)). | 10,000-term chain on a 512 KiB thread gives an error, not a crash. |
| BASES-INV-26 | Tiles: http(s) only, ephemeral session without cookies or credentials, 32 MB memory cache, no disk cache, 4 MB per tile; first template replaces Apple's map ([BaseTiledMapView.swift:16](../../../Sources/GraphiteUI/BaseTiledMapView.swift#L16), [BaseTiledMapView.swift:31-38](../../../Sources/GraphiteUI/BaseTiledMapView.swift#L31-L38), [BaseTiledMapView.swift:227](../../../Sources/GraphiteUI/BaseTiledMapView.swift#L227)). | Existing `UiBasesMapTilesTests`. |
| BASES-INV-27 | Tile template placeholders and their values: `{z}`, `{x}`, `{y}`, `{ratio}` (`@2x` at scale > 1), `{quadkey}`, `{prefix}`, `{bbox-epsg-3857}` ([BaseMapTiles.swift:40](../../../Sources/GraphiteCore/BaseMapTiles.swift#L40), [BaseMapTiles.swift:67-97](../../../Sources/GraphiteCore/BaseMapTiles.swift#L67-L97)); one URL without `{z}{x}{y}` is a style ([BaseMapTiles.swift:24](../../../Sources/GraphiteCore/BaseMapTiles.swift#L24)). | Existing `CoreBasesMapTilesTests`. |
| BASES-INV-28 | `html()` keeps only listed inline formatting; links only http, https, mailto; images never fetched ([BaseHTMLText.swift:64-82](../../../Sources/GraphiteCore/BaseHTMLText.swift#L64-L82), [BaseHTMLText.swift:331-334](../../../Sources/GraphiteCore/BaseHTMLText.swift#L331-L334)). | Existing fuzz of 2,000 fragments in `CoreBasesHTMLTests`. |
| BASES-INV-29 | Thumbnails: 640 px maximum dimension, 32 MiB budget, remote images ≤ 32 MiB, invalidated by file modification date and size ([BaseValueViews.swift:409-412](../../../Sources/GraphiteUI/BaseValueViews.swift#L409-L412), [BaseValueViews.swift:519-525](../../../Sources/GraphiteUI/BaseValueViews.swift#L519-L525)). | Existing thumbnail tests in `UiBasesDocumentModelTests`. |
| BASES-INV-30 | Embedded bases: 100 rows per step, model cache capacity 8, default height 420, map height `mapHeight` + 48, the map no taller than it is wide (at least 200) in a note narrower than 600 points ([BaseDocumentView.swift:51](../../../Sources/GraphiteUI/BaseDocumentView.swift#L51), [BaseDocumentView.swift:125](../../../Sources/GraphiteUI/BaseDocumentView.swift#L125), [BaseDocumentView.swift:224](../../../Sources/GraphiteUI/BaseDocumentView.swift#L224), [BaseEmbedding.swift](../../../Sources/GraphiteUI/BaseEmbedding.swift) `BaseEmbeddedHeight`). | Snapshot of an embedded table with 250 rows. |
| BASES-INV-31 | Header taps cycle ascending → descending → the view's sort, and never repeat an order ([BaseDocumentModel.swift:286-298](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L286-L298)). | Existing header-tap tests. |
| BASES-INV-32 | A `[[X.base#View]]` link selects the view by name; a missing name shows view 0 with a message ([BaseDocumentModel.swift:146-159](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L146-L159)); the selection follows its view by name across reloads ([BaseDocumentModel.swift:160-172](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L160-L172)). | Existing `testReloadKeepsTheSelectedView…`. |
| BASES-INV-33 | A Kanban move writes the column's value into the grouped note property; the "None" column clears it; formula and file groupings never move ([BaseDocumentModel.swift:553-592](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L553-L592)). | Existing `UiBasesKanbanTests`. |
| BASES-INV-34 | Record reuse: a row with unchanged size, modified, created and content-indexed flag yields the cached record ([BaseRecordReuse.swift:8-17](../../../Sources/GraphiteIndex/BaseRecordReuse.swift#L8-L17)). | Existing `UiBasesRecordReuseTests`. |
| BASES-INV-35 | The fast scalar decode and `JSONDecoder` give identical nodes for every stored property JSON ([BaseRecordQueries.swift:292-337](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L292-L337)). | Property test: encode random nodes with `JSONEncoder`, decode both ways. |
| BASES-INV-36 | Frontmatter typing: declared type wins; plain `true/True/TRUE` are booleans; plain decimal numbers are numbers; Obsidian's date pattern makes dates; text that is exactly one link becomes a link ([BaseFileRecord.swift:99-141](../../../Sources/GraphiteCore/BaseFileRecord.swift#L99-L141)). | Table test over `007`, `"007"`, `!!str 7`, `2025-01-01`, `[[A]]`. |
| BASES-INV-37 | Remote covers load only http(s); a note cannot make a card read `file://` ([BaseQuery.swift:407-412](../../../Sources/GraphiteCore/BaseQuery.swift#L407-L412)). | `file:///etc/hosts` cover gives no image. |

### Tests that become possible once the seams exist

- `BaseRecordProviderContractTests`: one fixture vault (aliases, duplicate names, rooted and relative links, Markdown and Wikilinks, `:` targets, non-ASCII case) run against every provider, including failure injection.
- Prefilter superset property test over generated vaults and filters, comparing `BaseRecordSource` fake output with and without requirements.
- `BaseDocumentModel` tests with `BaseRecordSource` and `BaseFileAccess` fakes: revision conflicts between read and save, index refresh failure after a saved property, latest-request ordering without `Task.sleep`.
- Evaluator tests in a fixed time zone and calendar independent of the test machine.
- Per-library unit tests (`BaseTextMethods`, `JavaScriptText`) without constructing an evaluator.
- Option-key round-trip test: for every `BaseViewOptionKey` and alias, set → read gives the set value, including nil.

## 8. Appendix: raw metrics

**Reconnaissance numbers, checked:**

| Metric | Reconnaissance | Checked value | How checked |
| --- | --- | --- | --- |
| Files / physical / code lines | 26 / 10,841 / 8,679 | Physical counts match each file's last line in `read_files` | read every file completely |
| `BaseEvaluator` type size | 1,005 code lines | Accepted | declaration spans [BaseEvaluator.swift:24-1223](../../../Sources/GraphiteCore/BaseEvaluator.swift#L24-L1223) |
| `default:` in `BaseEvaluator.swift` | 41 | 41: 20 over `BaseValue`, 3 over `BaseBinaryOperator`, 17 over names, 1 over `Character` | grep `default:` then classified by reading each line |
| `default:` in the area | 101 | Not recounted | — |
| `try?` | 27 | 27 | grep `try\?` over `Sources/Graphite*/Base*.swift` gave 30 lines; 3 are `entry?.` false matches ([BaseFileRecord.swift:214](../../../Sources/GraphiteCore/BaseFileRecord.swift#L214), [BaseDocumentModel.swift:608](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L608), [BaseDefinitionEditor.swift:696](../../../Sources/GraphiteCore/BaseDefinitionEditor.swift#L696)) |
| `.shared` | 1 | 1 (`URLSession.shared`, [BaseValueViews.swift:452](../../../Sources/GraphiteUI/BaseValueViews.swift#L452)) | reading |
| `static var` | 2 | 2, both computed (no mutable static state): [BaseDateSupport.swift:234](../../../Sources/GraphiteCore/BaseDateSupport.swift#L234), [BaseEmbedding.swift:40](../../../Sources/GraphiteUI/BaseEmbedding.swift#L40) | reading |
| `@unchecked Sendable` | 1 | 1, with a stated invariant ([BaseTiledMapView.swift:68-70](../../../Sources/GraphiteUI/BaseTiledMapView.swift#L68-L70)) | reading |
| `Date()`/`Date.now` | 1 | 1 `Date()` ([BasePropertyEditorSheet.swift:126](../../../Sources/GraphiteUI/BasePropertyEditorSheet.swift#L126)); plus 4 `.now` reads the pattern missed: [BaseEvaluator.swift:10](../../../Sources/GraphiteCore/BaseEvaluator.swift#L10), [BaseDocumentModel.swift:185](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L185), [BaseDocumentModel.swift:195](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L195) (two on one line), [BasePropertyEditorSheet.swift:138](../../../Sources/GraphiteUI/BasePropertyEditorSheet.swift#L138) | reading |
| `FileManager.default` | 2 | 2 ([BaseDocumentModel.swift:444](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L444), [BaseValueViews.swift:523](../../../Sources/GraphiteUI/BaseValueViews.swift#L523)) | reading |
| `URLSession` | 6 | Accepted | — |
| `Task { }` | 25 | 25: 17 in views, 1 model chain ([BaseDocumentModel.swift:504](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L504)), 1 thumbnail decode ([BaseValueViews.swift:488](../../../Sources/GraphiteUI/BaseValueViews.swift#L488)), 6 `Task.detached` | grep `Task \{|Task\.detached` |

**Functions over 40 code lines (reconnaissance, accepted; 29):** `BaseEvaluator.callFunction` 109, `YAMLSplicer.sequenceLines` 75, `BaseDateFormatting.text` 63, `BaseValueView.body` 62, `BaseDocumentModel.runQuery` 62, `JavaScriptReplacementTemplate.expansion` 57, `BaseEvaluator.evaluate` 56, `BaseEvaluator.stringMethod` 55, `YAMLSplicer.mappingLines` 55, `BaseExpressionParser.parsePrimary` 54, `BaseContainerView.body` 53, `BaseExpressionTokenizer.tokens` 53, `Parser.readTag` 52, `Parser.openElement` 52, `BaseDocumentModel.reload` 51, `BasePropertyDraft.init` 49, `VaultIndex.linkCondition` 49, `BaseCardsView.card` 46, `BaseQueryEngine.run` 46, `BaseViewEditorSheet.body` 45, `BaseEvaluator.field` 45, `BaseTableView.headerRow` 44, `BaseKanbanView.card` 44, `WrittenYAMLNode.init` 44, `BaseDefinition.read` 44, `BaseToolbar.body` 43, `BaseRecordPrefilter.requirement` 43, `VaultIndex.baseRecords` 42, `BaseListView.item` 41.

**Types over 300 code lines:** `BaseEvaluator` 1,005, `BaseDocumentModel` 456, `extension BaseHTMLText` 328 (reconnaissance, accepted).

**Files over 400 code lines:** `BaseEvaluator.swift` 1,113, `BaseDefinitionEditor.swift` 846, `BaseValueViews.swift` 515, `BaseDocumentModel.swift` 505, `BaseDocumentView.swift` 494, `BaseValue.swift` 450, `BaseDefinition.swift` 431, `BaseExpression.swift` 416.

**Counted for this document:**

| Measure | Value | Method |
| --- | --- | --- |
| `BaseEvaluator` stored instance properties | 14 | reading lines 25-43 |
| `BaseEvaluator` methods | 58 | reading every `func` in lines 24-1227 (including `capitalizedFirstLetter`) |
| `BaseDocumentModel` stored instance properties | 28 | reading lines 21-67 |
| Writers of `actionErrorMessage` | 8 (5 in the model, 3 in the view) | reading |
| Link-resolution implementations | 5 | reading (SRP-BASES-03) |
| Places a new view type touches | 10 in 6 files (+2 map-only checks) | reading (OCP-BASES-02) |
| String dispatch `switch`es for the expression vocabulary | 14 (12 evaluator, 2 prefilter) | reading (OCP-BASES-01) |
| Frontmatter regular expressions in Core | 4 | grep `\\A---` |
| Static regular expressions built with `try?` | 7 | grep `try\? NSRegularExpression` |
| Core test call sites building an evaluator or engine without a provider | 21, plus 1 passing an explicit in-memory provider ([CoreAreaHandoffTests.swift:265](../../../Tests/GraphiteCoreTests/CoreAreaHandoffTests.swift#L265)) | grep `BaseQueryEngine\(\|BaseEvaluator\(formulas` in `Tests/**` |
| Test call sites with the index provider | 3 engine constructions in `GraphiteIndexTests` (`CoreAreaIndexHandoffTests.swift:48`, `BaseSampleVaultTests.swift:72`, `BaseIndexTests.swift:192`) plus direct provider use at `IndexFileOperationsFixTests.swift:242` (the "4" in LSP-BASES-01), and 1 in `GraphiteUITests` (`UiBasesReloadMeasurementTests.swift:36`) | same grep plus grep `baseRecordProvider` |
| Bases test classes | 27 (`Tests/**`) + 1 hosted (`App/Tests/BasesViewsTests.swift`) | grep `class \w*Base\w*Tests` |
| Unowned `Task {}` started by views | 17 | grep `Task \{` in UI files |

**Tests read and what they pin (sampled by reading):** `BaseTestRecords` builds records through `BaseFrontmatter.entries` and fixes `now` in the machine's zone ([BaseEvaluatorTests.swift:5-35](../../../Tests/GraphiteCoreTests/BaseEvaluatorTests.swift#L5-L35)); JavaScript number and text semantics ([BaseEvaluatorTests.swift:41-80](../../../Tests/GraphiteCoreTests/BaseEvaluatorTests.swift#L41-L80)); in-memory alias resolution and property backlinks ([CoreBasesDefinitionQueryEngineTests.swift:213-229](../../../Tests/GraphiteCoreTests/CoreBasesDefinitionQueryEngineTests.swift#L213-L229)); prefilter text requirement against stored JSON ([CoreBasesDefinitionQueryEngineTests.swift:198-209](../../../Tests/GraphiteCoreTests/CoreBasesDefinitionQueryEngineTests.swift#L198-L209)); index storage of properties, tags, links and provider answers ([BaseIndexTests.swift:27-68](../../../Tests/GraphiteIndexTests/BaseIndexTests.swift#L27-L68)); prefilter SQL narrowing ([BaseIndexTests.swift:106-120](../../../Tests/GraphiteIndexTests/BaseIndexTests.swift#L106-L120)); the model on a real temporary vault and index ([UiBasesDocumentModelTests.swift:12-45](../../../Tests/GraphiteUITests/UiBasesDocumentModelTests.swift#L12-L45)), older-reload ordering via a 20 ms sleep ([UiBasesDocumentModelTests.swift:180-197](../../../Tests/GraphiteUITests/UiBasesDocumentModelTests.swift#L180-L197)) and root-first link following ([UiBasesDocumentModelTests.swift:201-212](../../../Tests/GraphiteUITests/UiBasesDocumentModelTests.swift#L201-L212)). No test edits `defaultZoom` through an alias (grep `zoom` in `Tests/**`), and no test uses a root-level merge key (grep `<<:` in `Tests/**`; all 7 hits are inside `views`).

**Code lines by module (sum of the reconnaissance table):** Core 13 files, 5,059 code lines; Index 2 files, 321; UI 11 files, 3,299; total 8,679. Correction: section 1 states the Core share as 4,629; the correct figure is 5,059.

## 9. Since the snapshot

Delta audit of 2026-10-19 at `fff794b` (main), against `FR-01` to `FR-108`. Four commits changed this area's files (361 lines added, 101 removed): `a6672f6` (the `hasLink(file("Name"))` prefilter), `827c03b` (two-column cards, toolbar count), `ea07e7f` (phone table, list, Kanban and map) and `6b80826` (embedded-base loading). No file is new. The UI changes add pure layout deciders (`BaseCardGridMetrics`, `BaseListInlineSeparator`, `BaseKanbanColumnMetrics`, `BaseTableLayout`, `BaseEmbeddedHeight`). Invariant touched: B-26 (`BASES-INV-30`).

### New findings

#### CC-BASES-11 The phone breakpoint is declared four times and decided by four guards with two rules
- **Severity:** Medium
- **Rule:** `FR-24`, `FR-10`
- **Evidence:** `compactWidthThreshold: CGFloat = 600` is declared in four types: [BaseCardsAndListViews.swift:11](../../../Sources/GraphiteUI/BaseCardsAndListViews.swift#L11), [BaseKanbanView.swift:18](../../../Sources/GraphiteUI/BaseKanbanView.swift#L18), [BaseTableView.swift:12](../../../Sources/GraphiteUI/BaseTableView.swift#L12), [BaseEmbedding.swift:119](../../../Sources/GraphiteUI/BaseEmbedding.swift#L119). Three guards reject a zero or infinite width ([BaseKanbanView.swift:34](../../../Sources/GraphiteUI/BaseKanbanView.swift#L34), [BaseTableView.swift:21](../../../Sources/GraphiteUI/BaseTableView.swift#L21), [BaseEmbedding.swift:145](../../../Sources/GraphiteUI/BaseEmbedding.swift#L145)); the cards guard only compares ([BaseCardsAndListViews.swift:26](../../../Sources/GraphiteUI/BaseCardsAndListViews.swift#L26)), so a width of 0 is compact for cards and regular for the other three. The same `onGeometryChange(for: CGFloat.self)` width line is written four times ([BaseCardsAndListViews.swift:69](../../../Sources/GraphiteUI/BaseCardsAndListViews.swift#L69), [BaseKanbanView.swift:84](../../../Sources/GraphiteUI/BaseKanbanView.swift#L84), [BaseTableView.swift:134](../../../Sources/GraphiteUI/BaseTableView.swift#L134), [BaseEmbedding.swift:133](../../../Sources/GraphiteUI/BaseEmbedding.swift#L133)). Introduced in `827c03b` and `ea07e7f`.
- **Why it matters:** one constant drives the whole iPhone layout of Bases. A missed copy leaves an embedded base whose map, table and cards switch to the phone layout at different widths.
- **Fix direction:** one width class (`BaseLayoutWidth.isCompact(_:)`) holds the threshold and the finite, positive guard; the four metric types take its result, and one width-measuring modifier replaces the four `onGeometryChange` lines.

#### CC-BASES-12 Every table cell runs the first-column pin's per-frame visual effect, not only the first column's
- **Severity:** Medium
- **Rule:** `FR-104`, `FR-107`
- **Evidence:** `pinnedToLeadingEdge` adds two `AnyShapeStyle` backgrounds, a `visualEffect` closure that reads the frame in the scroll view's coordinates, and a `zIndex` ([BaseTableView.swift:345-354](../../../Sources/GraphiteUI/BaseTableView.swift#L345-L354)). It is applied to every header ([:167](../../../Sources/GraphiteUI/BaseTableView.swift#L167)), body ([:265](../../../Sources/GraphiteUI/BaseTableView.swift#L265)) and summary cell ([:329](../../../Sources/GraphiteUI/BaseTableView.swift#L329)) with `position == 0 && pinsFirstColumn` as a value, so a sideways scroll runs the closure for every visible cell on every frame: about 200 calls for 8 columns and 25 rows, of which about 26 produce an offset. Pinning is on for iPad and Mac too whenever the first column is at most 55% of the view ([BaseTableView.swift:27-30](../../../Sources/GraphiteUI/BaseTableView.swift#L27-L30)). No benchmark is recorded. Introduced in `ea07e7f`.
- **Why it matters:** the table is the Bases view where scrolling cost is most visible, on every platform.
- **Fix direction:** build each row's first cell outside the `ForEach` over the other columns, so only that view carries the modifier; record horizontal-scroll frame time before and after.

#### CC-BASES-13 The `hasLink(file(…))` branch repeats the arms of the switch below it and adds another `default:` over `BaseValue`
- **Severity:** Low
- **Rule:** `FR-24`, `FR-18`
- **Evidence:** the new branch maps `.string` and non-external `.link` to `.linksTo(.target(…))` ([BaseRecordPrefilter.swift:122-128](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L122-L128)); the existing switch writes the same two arms ([:129-134](../../../Sources/GraphiteCore/BaseRecordPrefilter.swift#L129-L134)); both end in `default: return nil`. Introduced in `a6672f6`.
- **Why it matters:** the prefilter's superset contract depends on these arms matching, and a new link-like `BaseValue` case falls silently into either `default:`.
- **Fix direction:** one `linkTargetRequirement(for: BaseValue)` with an exhaustive switch, called by both paths.

#### CC-BASES-14 New layout sizes are bare literals, and the new named constants carry no unit
- **Severity:** Low
- **Rule:** `FR-78`, `FR-81`
- **Evidence:** `spacing = isCompact ? 12 : 16` and `padding = isCompact ? 12 : 16` ([BaseCardsAndListViews.swift:27-28](../../../Sources/GraphiteUI/BaseCardsAndListViews.swift#L27-L28)); `14 : 18`, `6 : 8` and `10 : 12` in the cards view (lines 59, 100, 118); Kanban spacing and margins ([BaseKanbanView.swift:36-41](../../../Sources/GraphiteUI/BaseKanbanView.swift#L36-L41)); `minimumCardWidth`, `compactWidthThreshold`, `nextColumnPeekWidth`, `regularColumnWidth`, `mapToolbarHeight`, `minimumCompactMapHeight` without a unit ([BaseKanbanView.swift:16-24](../../../Sources/GraphiteUI/BaseKanbanView.swift#L16-L24), [BaseEmbedding.swift:117-121](../../../Sources/GraphiteUI/BaseEmbedding.swift#L117-L121)). Introduced in `827c03b` and `ea07e7f`; extends `CC-BASES-09`.
- **Why it matters:** the compact and regular margins of cards and Kanban are one design token written six times, and the views drift apart one tweak at a time.
- **Fix direction:** one `BaseLayoutMetrics` with regular and compact `spacingPoints`, `marginPoints` and `cardPaddingPoints`, and `…Points` on every size constant.

#### CC-BASES-15 The toolbar count is put together in code from English fragments
- **Severity:** Low
- **Rule:** `FR-55`
- **Evidence:** `countText(showsNoun:)` concatenates `"\(displayed) of "`, the count and `" result"`/`" results"` with the plural chosen by `== 1` ([BaseDocumentView.swift:590-596](../../../Sources/GraphiteUI/BaseDocumentView.swift#L590-L596)); the same string is the accessibility label ([:584-588](../../../Sources/GraphiteUI/BaseDocumentView.swift#L584-L588)). Introduced in `827c03b`.
- **Why it matters:** no string catalogue entry can reorder "N of M results" or apply another language's plural rules.
- **Fix direction:** plural-aware catalogue keys for both forms, chosen by `ViewThatFits` as now.

#### CC-BASES-16 The list separator runs a regular expression for every row on every render
- **Severity:** Low
- **Rule:** `FR-62`, `FR-69`
- **Evidence:** `BaseListInlineSeparator.init` calls `separator.replacing(/\s+$/, with: "")` ([BaseCardsAndListViews.swift:151](../../../Sources/GraphiteUI/BaseCardsAndListViews.swift#L151)); a separator is built per row in `inlineValues` ([:226](../../../Sources/GraphiteUI/BaseCardsAndListViews.swift#L226)), which every body evaluation calls ([:212](../../../Sources/GraphiteUI/BaseCardsAndListViews.swift#L212)). The separator is the same for the whole view. Introduced in `ea07e7f`.
- **Why it matters:** a list of 100 rows matches the same pattern 100 times per render for a value that changes only with the `.base` file.
- **Fix direction:** build the separator once per result and trim with a suffix scan.

#### CC-BASES-17 `columnWidths(for:viewWidth:)` has a default that only a test uses
- **Severity:** Low
- **Rule:** `FR-32`
- **Evidence:** `viewWidth: CGFloat? = nil` ([BaseTableView.swift:77](../../../Sources/GraphiteUI/BaseTableView.swift#L77)); production always passes the width ([:87](../../../Sources/GraphiteUI/BaseTableView.swift#L87)); only `UiBasesColumnResizeTests.swift:62` uses the default. Introduced in `ea07e7f`.
- **Why it matters:** the test pins the width rule as it is before layout, which no laid-out table uses.
- **Fix direction:** remove the default and pass an explicit width in the test.

### State changes of earlier findings
- `CC-BASES-01`: Open → **Partly fixed**. Three listed functions are now under 40 code lines (`BaseCardsView.card` about 36, `BaseTableView.headerRow` 30, `BaseListView.item` 32), so the count goes from 29 to 26.
- `CC-BASES-06`, `ISP-BASES-03`, `CC-BASES-02`, `CC-BASES-09`: unchanged.

### Patterns to keep
- The grouping name has one owner in Core: `BaseQueryEngine` computes `groupDisplayName` once ([BaseQuery.swift:133](../../../Sources/GraphiteCore/BaseQuery.swift#L133)), and the table, cards and list read it.
- Layout decisions are pure values with value tests, including NaN, infinity and zero (`UiBasesPhoneLayoutTests`, `UiBasesCardGridTests`).
- The pin keeps a stable view identity: it is applied with a `Bool`, never through `if`/`else`, and moves the cell through `visualEffect` without a layout pass.
- The embed loading signal belongs to the host: the note declares `LivePreviewEmbedLoadingKey` and the base only reports into it ([BaseDocumentView.swift:418](../../../Sources/GraphiteUI/BaseDocumentView.swift#L418)).
