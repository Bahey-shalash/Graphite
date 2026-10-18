# Read Aloud: document model, speech, neural voices, player UI (VOICE)
Snapshot: b13dec3 (main, 2026-10-18).
Scope: `Sources/GraphiteCore/` (16 Read Aloud, math-speech and neural-voice files), `Sources/GraphiteApple/` (4 Read Aloud files and `Resources/MathSpeech/math-speech.js`), `Sources/GraphiteUI/` (20 Read Aloud, PDF reading and voice-settings files), `Sources/GraphiteVoices/` (12 files), 53 files, 10005 physical lines, 8116 code lines (method: blank and comment-only lines and string contents removed by the reconnaissance script).

| Principle | Verdict | Reason |
| --- | --- | --- |
| S | Weak | `ReadAloudController` holds 39 stored properties across 8 jobs; `ReadAloudDocument.markdown` is 273 code lines and `pageText` 149; `ReadAloudNavigator` holds 19 stored properties across 7 jobs. |
| O | Mixed | A new neural model family is wired in 7 places across 3 files; the quality, mode and passage-audio policies are closed enums with pure deciders. |
| L | Weak | The system-voice and neural adapters of `ReadAloudSpeaking` disagree on 7 contract points, including speed (0.5–3× against 0.5–1.5×) and route changes; four functions named `stop` have four scopes. |
| I | Mixed | `ReadAloudSpeaking` has 16 requirements covering 6 concerns; views reach through the controller into the session on 67 lines. |
| D | Mixed | A static service locator (`ReadAloudVoices`) has 11 references and 5 initializers construct I/O in default arguments; the renderer and aligner are injected through real seams. |
| Clean code | Mixed | 19 functions exceed 40 code lines; 9 `Task.sleep` calls include one sleep-poll loop; 15 persisted keys and one preference-suite name sit in 8 files under two naming styles; 7 members are dead. |

## 1. Summary

**What the area does.** Read Aloud turns a Markdown note or PDF pages into bounded spoken passages with exact UTF-16 source mappings (Core `ReadAloudDocument`, pronunciations, math speech, reanchoring, folding). It then speaks them through one of two adapters of the `ReadAloudSpeaking` protocol. `AppleReadAloudSpeech` drives `AVSpeechSynthesizer`. `NeuralReadAloudSpeech` plays passages that MLX voices rendered ahead of time, checked them, aligned with on-device recognition and cached in Caches. A window-owned `ReadAloudController` prepares documents and runs the lazy PDF page pipeline. `ReadAloudNavigator` steers sections, the listening queue, remembered places and the Read Aloud pen. SwiftUI views (`ReadAloudFloatingPlayer`, `ReadAloudControls`, `ReadAloudReader`, the settings pages) drive all of it.

The layering is sound: Core imports only Foundation, swift-markdown and CryptoKit. But three objects (`ReadAloudController`, `ReadAloudSession`, `ReadAloudNavigator`) carry most of the orchestration, and views call the session directly.

**The three biggest problems.**
1. **Stopping is not one operation.** The floating player's Stop calls `ReadAloudNavigator.stopAndRewind`, which stops only the session ([ReadAloudNavigator.swift:174-178](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L174-L178)). The popover's Stop and the close button call `ReadAloudController.clear` ([ReadAloudControls.swift:208-211](../../../Sources/GraphiteUI/ReadAloudControls.swift#L208-L211), [ReadAloudFloatingPlayer.swift:335](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L335)). Preparation tasks that nothing cancels then restart reading after the person pressed Stop (BUG-VOICE-01, BUG-VOICE-02). Separately, `ReadAloudSession.stop` gives up the audio session on every sentence skip and every PDF page change (BUG-VOICE-03).
2. **The two speech adapters are not substitutable.** High Quality playback has four defects:
   - it caps speed at 1.5× while the UI offers 3× (BUG-VOICE-04);
   - it hides the speed control under VoiceOver although the system rate does not apply to it (BUG-VOICE-05);
   - it ignores route changes (BUG-VOICE-08);
   - it keeps the model loaded after cancellation (BUG-VOICE-07).

   The protocol's default implementations drop request fields that the test fakes rely on (LSP-VOICE-02). Seven types have no test: `NeuralReadAloudSpeech`, `ReadAloudPassagePreparation`, `RenderedPassagePlayer`, the `ReadAloudAudioCache` actor, `NeuralVoiceDownloader`, `NeuralVoiceLibrary` and `ReadAloudNavigator` (grep of `Tests/**` and `App/Tests/**` for these names returns no match).
3. **God objects with flag-driven state.** `ReadAloudController` has 39 stored properties. It owns Markdown preparation, the PDF page pipeline, PDF and note reanchoring, scan review, the follow-reading policy, Now Playing and sheet flags. `ReadAloudSession` encodes its playback flow as an enum plus the flags `needsRestart`, `wasSpeakingWhenInterrupted` and `lacksWordTiming`, plus a sentinel offset ([ReadAloudSpeech.swift:557](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L557), [ReadAloudSpeech.swift:796](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L796)). `ReadAloudDocument.markdown` is the longest function in the app.

**The three best parts.**
1. **Exact source mapping that refuses to guess.** Spans carry UTF-16 speech and source ranges. A partial equation or a partial formatted run is rejected rather than guessed ([ReadAloudDocument.swift:347](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L347), [ReadAloudDocument.swift:447](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L447)). Rendered-view alignment requires full ordered agreement ([ReadingSourceAlignment.swift:55-58](../../../Sources/GraphiteUI/ReadingSourceAlignment.swift#L55-L58)). PDF highlights re-check text and composed-character boundaries before drawing ([PDFReadAloudSource.swift:217-226](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L217-L226)).
2. **Stale-callback discipline.** Every utterance carries a fresh request `UUID`. The Apple adapter clears its active utterance before cancelling, so a cancelled utterance can never advance a replacement ([ReadAloudSpeech.swift:320-333](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L320-L333)). The session drops events from any other request ([ReadAloudSpeech.swift:773](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L773), [ReadAloudSpeech.swift:793](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L793)). The controller's `preparationIdentifier` makes the latest preparation win ([ReadAloudController.swift:115](../../../Sources/GraphiteUI/ReadAloudController.swift#L115), [ReadAloudController.swift:660](../../../Sources/GraphiteUI/ReadAloudController.swift#L660)).
3. **Pure, tested Core policies for the neural path.** Seven rules are value-level and pinned by `NeuralReadAloudTests.swift` (21 tests, grep `func test` in that file):
   - cache keys ([ReadAloudAudioCachePolicy.swift:16-24](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L16-L24));
   - LRU eviction with protected keys ([ReadAloudAudioCachePolicy.swift:57-70](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L57-L70));
   - mode and passage-audio decisions ([ReadAloudQualityMode.swift:12-43](../../../Sources/GraphiteCore/ReadAloudQualityMode.swift#L12-L43));
   - render checks, word alignment and voice-text mapping;
   - manifest validation ([NeuralVoiceManifest.swift:155-176](../../../Sources/GraphiteCore/NeuralVoiceManifest.swift#L155-L176)).

**Earlier-pass claims.** `Docs/SOLID.md` makes no claim about Read Aloud: grep for `read ?aloud|neural|voice|speech|Pronunciation` in it returns nothing. Claims in `Architecture.md`, `Coverage.md` and one code comment:

| Claim (source) | Verdict | Evidence |
| --- | --- | --- |
| `ReadAloudDocument` "rejects partial equations or unreliable mappings" ([Architecture.md:15](../../../Docs/Architecture.md#L15)) | Holds | [ReadAloudDocument.swift:347](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L347), [ReadAloudDocument.swift:447](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L447) |
| The session keeps the choice under `GraphiteReadAloudChosenVoice` ([Architecture.md:17](../../../Docs/Architecture.md#L17)) | Does not hold (stale); [Architecture.md:27](../../../Docs/Architecture.md#L27) contradicts it | The key is `GraphiteReadAloudVoiceChoice`; `GraphiteReadAloudChosenVoice` is deleted at init ([ReadAloudSpeech.swift:444](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L444), [ReadAloudSpeech.swift:451](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L451), [ReadAloudSpeech.swift:456](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L456)) |
| "The audio session stays active across that page break" ([Architecture.md:46](../../../Docs/Architecture.md#L46)) | Does not hold | `ReadAloudSession.load` calls `stop`, which calls `releaseAudio` ([ReadAloudSpeech.swift:546](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L546), [ReadAloudSpeech.swift:584](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L584)); see BUG-VOICE-03 |
| Speed 0.5×–3× ([Architecture.md:38](../../../Docs/Architecture.md#L38)) | Partly holds | Session range 0.5…3 ([ReadAloudSpeech.swift:446](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L446)); pickers offer 0.75…3 ([ReadAloudVoiceSettings.swift:19](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L19)); High Quality plays at most 1.5× ([RenderedPassagePlayer.swift:39](../../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L39)) |
| `RenderedPassagePlayer`: "interruptions stop and report as the system voice's did" ([Architecture.md:31](../../../Docs/Architecture.md#L31)) | Partly holds | Interruptions are handled ([NeuralReadAloudSpeech.swift:273-286](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L273-L286)); route changes and media-services resets are not, unlike [ReadAloudSpeech.swift:171-173](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L171-L173) |
| The cache "removes the least recently used passages past 250 MiB, never those of the document being read" ([Architecture.md:31](../../../Docs/Architecture.md#L31)) | Holds | [ReadAloudAudioCachePolicy.swift:52-70](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L52-L70), [ReadAloudAudioCache.swift:133-139](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L133-L139), [ReadAloudPassagePreparation.swift:133-135](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L133-L135) |
| A rejected rendering "is left to the system voice (`systemVoiceTexts`)" ([Architecture.md:33](../../../Docs/Architecture.md#L33)) | Partly holds | The system voice does read it, because `waitForPassage` returns nil ([NeuralReadAloudSpeech.swift:95-96](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L95-L96)); `systemVoiceTexts` is written ([ReadAloudPassagePreparation.swift:203](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L203)) and never read |
| `ReadAloudAudioTiming` is "a tested foundation … not an integrated audio player" ([Architecture.md:23](../../../Docs/Architecture.md#L23)) | Holds | No production caller (grep `ReadAloudAudioTiming` in `Sources/**` matches only its declaration) |
| "Read Aloud lists its voices the first time something needs them" ([Coverage.md:197](../../../Docs/Coverage.md#L197)) | Holds, through a getter with side effects | [ReadAloudSpeech.swift:421-424](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L421-L424) |
| The navigator "remembers the last place per note (source location) and PDF (page) in user defaults" ([Architecture.md:38](../../../Docs/Architecture.md#L38)) | Holds | [ReadAloudNavigator.swift:387-395](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L387-L395) |
| "The app's one set of downloadable voices, shared by every window" ([ReadAloudVoices.swift:9-10](../../../Sources/GraphiteUI/ReadAloudVoices.swift#L9-L10)) | Holds today only because there is one workspace | iPadOS and iPhone run one scene ([GraphiteApp.swift:21](../../../App/GraphiteApp.swift#L21)); the Mac has one `Window` ([GraphiteMacScenes.swift:23-28](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L23-L28)) |

## 2. File inventory

Physical and code lines are the reconnaissance numbers; physical lengths agree with the `read_files` totals (which count the final newline as one more line).

| File | Physical | Code | Responsibility |
| --- | ---: | ---: | --- |
| [GraphiteApple/PDFReadAloudPage.swift](../../../Sources/GraphiteApple/PDFReadAloudPage.swift) | 362 | 328 | PDF page snapshot value, scan-correction rebuild, `PDFReadAloudExtraction` actor (layout order, recognition) |
| [GraphiteApple/ReadAloudLanguage.swift](../../../Sources/GraphiteApple/ReadAloudLanguage.swift) | 41 | 31 | Passage language recognition with NaturalLanguage |
| [GraphiteApple/ReadAloudMarkdownPreparation.swift](../../../Sources/GraphiteApple/ReadAloudMarkdownPreparation.swift) | 92 | 77 | Actor owning the JavaScriptCore math interpreter; vault pronunciation file read |
| [GraphiteApple/ReadAloudSpeech.swift](../../../Sources/GraphiteApple/ReadAloudSpeech.swift) | 902 | 698 | Voice value, `ReadAloudSpeaking` protocol, `AppleReadAloudSpeech` adapter, `ReadAloudSession` playback model, request and choice values |
| [GraphiteCore/MathSpeech.swift](../../../Sources/GraphiteCore/MathSpeech.swift) | 125 | 117 | Pure-Swift LaTeX subset (default interpreter, used by the reading-view token build) |
| [GraphiteCore/MathematicalSpeechStyle.swift](../../../Sources/GraphiteCore/MathematicalSpeechStyle.swift) | 4 | 4 | Concise or detailed enum |
| [GraphiteCore/NeuralVoiceManifest.swift](../../../Sources/GraphiteCore/NeuralVoiceManifest.swift) | 200 | 132 | Downloadable-voice manifest model, validation, download addresses |
| [GraphiteCore/PCMWaveFile.swift](../../../Sources/GraphiteCore/PCMWaveFile.swift) | 32 | 29 | 16-bit mono WAVE encoder (benchmark only) |
| [GraphiteCore/ReadAloudAudioCachePolicy.swift](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift) | 71 | 46 | Cache key, cache entry, LRU eviction decision |
| [GraphiteCore/ReadAloudAudioTiming.swift](../../../Sources/GraphiteCore/ReadAloudAudioTiming.swift) | 91 | 77 | Character-timing validation (no production caller) |
| [GraphiteCore/ReadAloudDocument.swift](../../../Sources/GraphiteCore/ReadAloudDocument.swift) | 727 | 631 | Span, passage, document values; plain-text, PDF-page and Markdown narration builders; abbreviations; errors |
| [GraphiteCore/ReadAloudFolding.swift](../../../Sources/GraphiteCore/ReadAloudFolding.swift) | 53 | 40 | Hidden ranges from folds and collapsed callouts |
| [GraphiteCore/ReadAloudPronunciationTerms.swift](../../../Sources/GraphiteCore/ReadAloudPronunciationTerms.swift) | 92 | 74 | Built-in term list |
| [GraphiteCore/ReadAloudPronunciations.swift](../../../Sources/GraphiteCore/ReadAloudPronunciations.swift) | 295 | 215 | Respelling rules (words, units, subscripts, symbols); vault file codec |
| [GraphiteCore/ReadAloudQualityMode.swift](../../../Sources/GraphiteCore/ReadAloudQualityMode.swift) | 44 | 28 | Mode and passage-audio decisions, prepared share |
| [GraphiteCore/ReadAloudReanchoring.swift](../../../Sources/GraphiteCore/ReadAloudReanchoring.swift) | 79 | 60 | Finding the sentence being read in edited text |
| [GraphiteCore/ReadAloudRenderCheck.swift](../../../Sources/GraphiteCore/ReadAloudRenderCheck.swift) | 160 | 122 | Babbling checks: coverage, length, loops, silence |
| [GraphiteCore/ReadAloudSection.swift](../../../Sources/GraphiteCore/ReadAloudSection.swift) | 54 | 49 | Heading sections of a note |
| [GraphiteCore/ReadAloudSourceToken.swift](../../../Sources/GraphiteCore/ReadAloudSourceToken.swift) | 55 | 45 | Word and equation tokens for rendered-view alignment |
| [GraphiteCore/ReadAloudVoiceText.swift](../../../Sources/GraphiteCore/ReadAloudVoiceText.swift) | 114 | 83 | Acronym-as-written text for codec voices, ranges mapped back |
| [GraphiteCore/ReadAloudWordAlignment.swift](../../../Sources/GraphiteCore/ReadAloudWordAlignment.swift) | 194 | 154 | Recognized-word to passage-word alignment, timed words |
| [GraphiteUI/NeuralVoiceBenchmarkScreen.swift](../../../Sources/GraphiteUI/NeuralVoiceBenchmarkScreen.swift) | 85 | 72 | Launch-argument measuring screen |
| [GraphiteUI/NeuralVoiceSettings.swift](../../../Sources/GraphiteUI/NeuralVoiceSettings.swift) | 232 | 205 | Mode picker, downloadable-voice rows, credits, storage section |
| [GraphiteUI/PDFReadAloudSource.swift](../../../Sources/GraphiteUI/PDFReadAloudSource.swift) | 384 | 310 | PDF endpoints, selection capture, exported-to-live text alignment, highlight values, `PDFReadAloudHighlighter` |
| [GraphiteUI/PDFRecognizedReadingOverlay.swift](../../../Sources/GraphiteUI/PDFRecognizedReadingOverlay.swift) | 86 | 77 | Overlay views for recognized-word highlights |
| [GraphiteUI/ReadAloudController.swift](../../../Sources/GraphiteUI/ReadAloudController.swift) | 778 | 660 | Window reading orchestrator (section 3.1) |
| [GraphiteUI/ReadAloudControls.swift](../../../Sources/GraphiteUI/ReadAloudControls.swift) | 234 | 198 | Toolbar controls and controls popover |
| [GraphiteUI/ReadAloudEditorHooks.swift](../../../Sources/GraphiteUI/ReadAloudEditorHooks.swift) | 24 | 17 | Editor callback bundle; simultaneous-tap delegate |
| [GraphiteUI/ReadAloudFloatingPlayer.swift](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift) | 481 | 395 | Floating player view, transport button, chip style, panel background |
| [GraphiteUI/ReadAloudHighlightStyle.swift](../../../Sources/GraphiteUI/ReadAloudHighlightStyle.swift) | 32 | 26 | Highlight fill colour |
| [GraphiteUI/ReadAloudNavigator.swift](../../../Sources/GraphiteUI/ReadAloudNavigator.swift) | 423 | 305 | Sections, queue, remembered places, pen marks, range taps, layout frames, queue menu items |
| [GraphiteUI/ReadAloudNowPlaying.swift](../../../Sources/GraphiteUI/ReadAloudNowPlaying.swift) | 72 | 58 | Lock-screen information and remote commands |
| [GraphiteUI/ReadAloudPen.swift](../../../Sources/GraphiteUI/ReadAloudPen.swift) | 221 | 168 | Pen glyph, tap recognizer, marker view, palette observer |
| [GraphiteUI/ReadAloudPlayerPlacement.swift](../../../Sources/GraphiteUI/ReadAloudPlayerPlacement.swift) | 116 | 89 | Pure placement of the floating player |
| [GraphiteUI/ReadAloudPronunciationEditor.swift](../../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift) | 159 | 142 | Settings editor for the vault pronunciation file |
| [GraphiteUI/ReadAloudReader.swift](../../../Sources/GraphiteUI/ReadAloudReader.swift) | 364 | 342 | Reading Options sheet, scan review, section and page pickers |
| [GraphiteUI/ReadAloudSpelling.swift](../../../Sources/GraphiteUI/ReadAloudSpelling.swift) | 38 | 32 | System spelling dictionary lookup for hyphenation |
| [GraphiteUI/ReadAloudVoiceSettings.swift](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift) | 163 | 139 | System voice, speed, highlight mode, sample playback |
| [GraphiteUI/ReadAloudVoices.swift](../../../Sources/GraphiteUI/ReadAloudVoices.swift) | 57 | 41 | Static library and render queue; controller factory; background-download entry |
| [GraphiteUI/ReadingSourceAlignment.swift](../../../Sources/GraphiteUI/ReadingSourceAlignment.swift) | 75 | 63 | Rendered-text token agreement; environment keys |
| [GraphiteVoices/NeuralReadAloudSpeech.swift](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift) | 288 | 239 | Neural `ReadAloudSpeaking` adapter: routing, playback, word timer, audio session |
| [GraphiteVoices/NeuralSpeechEngine.swift](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift) | 252 | 187 | MLX model load and render actor |
| [GraphiteVoices/NeuralVoiceBenchmark.swift](../../../Sources/GraphiteVoices/NeuralVoiceBenchmark.swift) | 251 | 213 | Device measurement runner |
| [GraphiteVoices/NeuralVoiceCatalog.swift](../../../Sources/GraphiteVoices/NeuralVoiceCatalog.swift) | 36 | 26 | Bundled manifest, Dia prompt, voices folder |
| [GraphiteVoices/NeuralVoiceDownloader.swift](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift) | 300 | 247 | Background URLSession downloads, resume data, retries, install trigger |
| [GraphiteVoices/NeuralVoiceInstallation.swift](../../../Sources/GraphiteVoices/NeuralVoiceInstallation.swift) | 84 | 64 | Voice folders, staging, marker, SHA-256 verification |
| [GraphiteVoices/NeuralVoiceLibrary.swift](../../../Sources/GraphiteVoices/NeuralVoiceLibrary.swift) | 194 | 146 | Observable voice states, selection, mode, preferences |
| [GraphiteVoices/ProcessResources.swift](../../../Sources/GraphiteVoices/ProcessResources.swift) | 71 | 54 | Memory footprint and thermal readings (benchmark) |
| [GraphiteVoices/ReadAloudAudioCache.swift](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift) | 145 | 111 | Cache actor: AAC writing, details, index, eviction |
| [GraphiteVoices/ReadAloudPassagePreparation.swift](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift) | 287 | 214 | Render protocol, MLX renderer, render queue with checks and fallback |
| [GraphiteVoices/ReadAloudSpeechAlignment.swift](../../../Sources/GraphiteVoices/ReadAloudSpeechAlignment.swift) | 118 | 94 | Aligner protocol and SpeechAnalyzer implementation |
| [GraphiteVoices/RenderedPassagePlayer.swift](../../../Sources/GraphiteVoices/RenderedPassagePlayer.swift) | 110 | 87 | AVAudioEngine player with time-pitch |
| [GraphiteApple/Resources/MathSpeech/math-speech.js](../../../Sources/GraphiteApple/Resources/MathSpeech/math-speech.js) | 58 | 55 | Generated MathJax and Speech Rule Engine bundle; its source is [Vendor/math-speech/entry.js](../../../Vendor/math-speech/entry.js) |

## 3. Responsibility maps of the major types

### 3.1 `ReadAloudController` (617 code lines in one block, 39 stored properties)

Stored properties counted by reading [ReadAloudController.swift:29-82](../../../Sources/GraphiteUI/ReadAloudController.swift#L29-L82) and [ReadAloudController.swift:553](../../../Sources/GraphiteUI/ReadAloudController.swift#L553).

| Responsibility | Stored state | Functions (line ranges in ReadAloudController.swift) |
| --- | --- | --- |
| Reading status for views | `session`, `showsReader`, `followsReading`, `isPreparing`, `title`, `scopeDescription`, `errorMessage`, `sourceHighlightNotice`, `stopIdentifier` (written, never read) | `isActive` (512), `stop` (414-422), `clear` (424-443), `begin` (591-625), `finishPreparing` (722-739), `failed` (741-751) |
| Device preferences | `preferences`, `mathematicalStyle`, `pdfReadingOrder`, `vaultRoot` | `init` (84-95), `chooseMathematicalStyle` (151-159), `choosePDFReadingOrder` (166-178) |
| Markdown preparation and edits | `markdownPreparation`, `markdownRequest`, `foldPreparationIdentifier`, `noteReanchoring`, `isReanchoringNote` | `readMarkdown` (97-119), `foldsDidChange` (124-149), `prepareVoiceSample` (161-164), `noteTextDidChange` (355-366), `reanchorNote` (368-400), `highlight(in:)` (454-457), `readingSourceText` (508) |
| PDF page pipeline and reanchoring | `pdfRequest`, `pdfSource`, `sourcePDF`, `sourcePDFRevision`, `readingPDFPage`, `readingPDFLastPage`, `pendingPosition`, `pdfContinuation`, `pdfRunningText`, `sourcePageIndex`, `sourceIdentifier` | `readPDF` (209-226), `readPDFSelection` (228-256), `readPDFRange` (258-286), `readPDFFromSelection` (288-294), `pdfContentDidChange` (301-304), `reanchorPDF` (311-341), `pauseForChange` (344-348), `continuePDFIfNeeded` (447-452), `highlights(in:)` (459-465), `showPDFPassage` (572-589), `loadPDFPage` (627-655), `preparePDFSnapshot` (657-720), `PDFSession.readAloudPage` (755-759) |
| Scanned-page review | `recognizedPDFPage`, `recognizedPageIdentifier`, `recognizedWordRange` | `correctRecognizedPDFWords` (180-182), `applyRecognizedPDFReview` (184-207) |
| Preparation lifecycle | `preparation`, `preparationIdentifier`, `playsWhenPrepared`, `playsCurrentPreparation` | shared by every reader above |
| Follow-reading policy | `followResumption` (and `followsReading`) | `suspendFollowing` (536-550), `shouldFollow` (555-561), `followResumptionDelay` (552) |
| Lock screen and High Quality status | `nowPlaying`, `neuralSpeech` | `followSessionForNowPlaying` (468-474), `updateNowPlaying` (476-503), `isWaitingForPreparedAudio` (515), `preparedAudioShare` (519-523), `preparingDescription` (526-529) |

**Calls that cross responsibilities (the coupling a split must preserve).**
- `begin` resets 26 fields from every group, cancels the note-reanchoring task and refreshes the voice list ([ReadAloudController.swift:591-625](../../../Sources/GraphiteUI/ReadAloudController.swift#L591-L625)).
- `preparePDFSnapshot` writes the running text, the scan-review state, `pdfRequest`, `pdfSource`, the notice and the continuation, then calls `finishPreparing` and `session.play` ([ReadAloudController.swift:687-719](../../../Sources/GraphiteUI/ReadAloudController.swift#L687-L719)).
- `finishPreparing` loads the session, gives the neural voice its language, consumes `pendingPosition` and opens the sheet ([ReadAloudController.swift:722-739](../../../Sources/GraphiteUI/ReadAloudController.swift#L722-L739)).
- `init` wires the session's end-of-document callback to the PDF continuation ([ReadAloudController.swift:93](../../../Sources/GraphiteUI/ReadAloudController.swift#L93)).

**Lifecycle and ordering rules it relies on.**
1. `begin` runs before every new read: it calls `stop` and `session.clear` and issues a new `preparationIdentifier` ([ReadAloudController.swift:592-593](../../../Sources/GraphiteUI/ReadAloudController.swift#L592-L593), [ReadAloudController.swift:623](../../../Sources/GraphiteUI/ReadAloudController.swift#L623)).
2. Every `await` in a preparation is followed by an identifier and cancellation check ([ReadAloudController.swift:115](../../../Sources/GraphiteUI/ReadAloudController.swift#L115), [ReadAloudController.swift:250](../../../Sources/GraphiteUI/ReadAloudController.swift#L250), [ReadAloudController.swift:660](../../../Sources/GraphiteUI/ReadAloudController.swift#L660), [ReadAloudController.swift:684](../../../Sources/GraphiteUI/ReadAloudController.swift#L684)). `foldsDidChange` uses a second identifier that `stop` never resets ([ReadAloudController.swift:131](../../../Sources/GraphiteUI/ReadAloudController.swift#L131)).
3. A page loads only when `sourcePDFRevision == pdf.readingTextVersion`; otherwise reading reanchors ([ReadAloudController.swift:629-632](../../../Sources/GraphiteUI/ReadAloudController.swift#L629-L632)).
4. `pdfContinuation` is set after a page is prepared and consumed once ([ReadAloudController.swift:712-715](../../../Sources/GraphiteUI/ReadAloudController.swift#L712-L715), [ReadAloudController.swift:448-450](../../../Sources/GraphiteUI/ReadAloudController.swift#L448-L450)); `stop`, `failed` and `pauseForChange` clear it.
5. `pendingPosition` is captured before `stop` in `reanchorPDF` and consumed in `finishPreparing` ([ReadAloudController.swift:328-335](../../../Sources/GraphiteUI/ReadAloudController.swift#L328-L335), [ReadAloudController.swift:730-736](../../../Sources/GraphiteUI/ReadAloudController.swift#L730-L736)).
6. The owner must assign `vaultRoot` before reading; it is not an init parameter ([ReadAloudController.swift:33](../../../Sources/GraphiteUI/ReadAloudController.swift#L33)).

**Verdict.** Weak single responsibility: one observable object is the Markdown reader, the PDF reader, the scan reviewer, the follow policy and the lock-screen publisher.

**Proposed split.**
- `MarkdownReading` owns `markdownRequest` and the fold and reanchor tasks with their identifiers. Members: `readMarkdown`, `foldsDidChange`, `noteTextDidChange`, `reanchorNote`, `chooseMathematicalStyle`, `prepareVoiceSample`, `highlight(in:)`.
- `PDFReading`, one per PDF read, has a state enum: `preparing(page)`, `reading(page)`, `awaitingReview(page)`, `paused(reason)`. It owns `pdfRequest`, `pdfSource`, the revision, the page identities, `pendingPosition`, the continuation and the running text. Members: the `readPDF*` entry points, `reanchorPDF`, `loadPDFPage`, `preparePDFSnapshot`, `highlights(in:)`, `showPDFPassage`.
- `ScannedPageReview` owns the three `recognized*` fields and `applyRecognizedPDFReview`.
- `FollowReadingPolicy` owns `followsReading`, the resumption task, `suspendFollowing` and `shouldFollow`.
- `ReadAloudController` keeps `session`, the active reading (`none`, `markdown(MarkdownReading)` or `pdf(PDFReading)`), the view flags, Now Playing, and one `stop(scope:)` that cancels the active reading's tasks.

### 3.2 `ReadAloudDocument` (579 code lines in one block; `markdown` 273 and `pageText` 149)

`ReadAloudDocument` stores three values (`passages`, `notices`, `runningText` at [ReadAloudDocument.swift:55-59](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L55-L59)). Its size comes from static builders.

| Responsibility | Members (line ranges in ReadAloudDocument.swift) |
| --- | --- |
| Value types | `ReadAloudSpan` (6-25), `ReadAloudPassageKind` (29-39), `ReadAloudPassage` (41-52), `ReadAloudError` (713-727) |
| Plain-text builder | `plainText` (64-72) |
| PDF page narration | `pageText` (79-237), in four parts:<br>• line segmentation and bullets (86-109)<br>• running header and footer detection (115-150)<br>• unit assembly with replacements (152-187)<br>• line joining and hyphenation (188-233)<br>Helpers: `lineEndHyphens`, `joinsHyphenatedBreak`, `hyphenationCandidates`, `dotLeader`, `leadingBulletLength` (239-292) |
| Markdown narration | `markdown` (296-589), in six parts:<br>• masking (306-326)<br>• math range merging and private-use markers (327-364)<br>• Obsidian extension masking (365-386)<br>• AST walk and source-location calibration (387-418)<br>• passage assembly with table cells, headings and callout titles (419-490)<br>• character-level source mapping for escapes, entities, smart punctuation and math markers (491-585) |
| Spoken replacements | `SpokenReplacement`, `spokenReplacements`, `abbreviationSpeech` (594-636) |
| Shared helpers | `removingQuoteMarkers`, `typographicSourceForms`, `readingRange`, `split` (640-710) |

**Ordering rules in `markdown`.**
1. Frontmatter, hidden ranges, comments and footnotes are masked before the style scan ([ReadAloudDocument.swift:319-327](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L319-L327)).
2. Masking keeps the UTF-16 length and the CR and LF units, so every offset still points into the original note ([ReadAloudDocument.swift:313-317](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L313-L317)).
3. Math markers are private-use scalars starting at U+E100 that do not occur in the note ([ReadAloudDocument.swift:342-350](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L342-L350)). Each marker replaces the first unit of its equation before parsing ([ReadAloudDocument.swift:362-363](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L362-L363)).
4. Each inline container is registered before its inline ranges, and lines are resolved after the walk ([ReadAloudDocument.swift:397-401](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L397-L401), [ReadAloudDocument.swift:418](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L418)).
5. A paragraph, a heading or a row's first cell flushes the current passage ([ReadAloudDocument.swift:467](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L467), [ReadAloudDocument.swift:478](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L478)).
6. A passage's `id` equals its index ([ReadAloudDocument.swift:705](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L705)).

**Verdict.** The responsibility is coherent (narrating a document), but it sits in two builders of 273 and 149 lines with 9 nested functions sharing mutable locals. No piece can be tested alone: the 25 tests in `ReadAloudDocumentTests.swift` (grep `func test`) pin whole outputs. The reading view and Live Preview call the same builder ([MarkdownPreview.swift:318](../../../Sources/GraphiteUI/MarkdownPreview.swift#L318), [LivePreviewWidgets.swift:148](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L148)), so every change crosses areas.

**Proposed split, each in its own Core file.**
- `MarkdownNarrationMasking` returns the prepared text and the math markers.
- `MarkdownNarrationLeaves` walks the AST and returns the leaves and the calibrated converter.
- `NarrationAssembler` holds the append, flush and split state as a struct with methods.
- `TextRunSourceMapper` maps characters to spans.
- `PDFPageLines` handles line segmentation and bullets.
- `RunningTextFilter` returns removed lines and running text as values.
- `HyphenationJoiner` and `SpokenReplacements` stand alone.
- `ReadAloudDocument` keeps the values and the three entry points.

### 3.3 `ReadAloudSession` (357 code lines, 24 stored properties)

| Responsibility | Stored state | Functions (line ranges in ReadAloudSpeech.swift) |
| --- | --- | --- |
| Playback state machine | `state`, `document`, `passageIndex`, `spokenRange`, `requestIdentifier`, `utteranceStartOffset`, `needsRestart`, `wasSpeakingWhenInterrupted`, `leadingPauseSeconds`, `didFinishDocument` | `load` (545-552), `play` (554-570), `pause` (572-580), `stop` (582-592), `clear` (594), `move` (596-604, 634-637), `seek` (653-662), sentence navigation (606-651), `speakCurrentPassage` (710-751), `receive` (753-807), `finishCurrentPassage` (825-840) |
| Highlight projection | `highlightMode`, `lacksWordTiming`, `voicesWithoutWordTiming`, `wordTimingCheck`, `speakingVoiceIdentifier` | `sourceRange` (469), `highlightRange` (473-479), `setHighlightMode` (481-484), `startWordTimingCheck` (811-823) |
| Voice catalogue and choice | `chosenVoiceIdentifier`, `listedVoices`, `hasListedVoices`, `readingLanguage`, `personalVoiceStatus` | `voices` (421-424), `refreshVoices` (486-490), `automaticVoice` to `canImproveVoiceByDownloading` (494-529), `systemSpeechSettingsName` and `voiceDownloadPath` (532-543), `chooseVoice` (666-673), `requestPersonalVoice` (676-686) |
| Speed and persistence | `speed`, `preferences` (keys at 444-452) | `init` (454-463), `setSpeed` (688-693), `prepareForVoiceOrSpeedChange` (695-702) |
| User messages | `message` | 11 assignments (551, 563, 594, 672, 682, 684, 714, 717, 744, 749, 768) |
| Dependency | `speech` | none |

**Cross-responsibility calls.**
- `speakCurrentPassage` resolves the voice and writes user messages ([ReadAloudSpeech.swift:712-721](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L712-L721)).
- `chooseVoice` and `setSpeed` pause playback ([ReadAloudSpeech.swift:668](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L668), [ReadAloudSpeech.swift:690](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L690)).
- `load` recomputes the reading language that the voice choice depends on ([ReadAloudSpeech.swift:549](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L549)).
- `stop` releases the audio route ([ReadAloudSpeech.swift:584](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L584)).

**Rules it relies on.**
1. Every move goes through `stop` first ([ReadAloudSpeech.swift:599](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L599), [ReadAloudSpeech.swift:656](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L656)).
2. `paused` with `needsRestart` means "speak again from `utteranceStartOffset`". `utteranceStartOffset` equal to the passage length while paused means "the passage ended during the pause" ([ReadAloudSpeech.swift:557](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L557), [ReadAloudSpeech.swift:796](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L796)).
3. `prepareAhead` is called before `speak` ([ReadAloudSpeech.swift:737-738](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L737-L738)).
4. The leading pause is consumed once ([ReadAloudSpeech.swift:730-731](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L730-L731)).

**Verdict and split.**
- `ReadAloudPlayback` holds a state enum: `idle`, `speaking(request, startOffset)`, `paused(resume: continueUtterance | restart(offset) | advance)`, `finished`. Only intent methods change it, replacing `needsRestart` and the sentinel offset.
- `ReadAloudVoiceSelection` holds the catalogue, the choice and the persisted `ReadAloudVoiceChoice`.
- `ReadAloudHighlightProjection` is a pure function of the passage, the spoken range, the mode and the timing flag.
- `ReadAloudSpeechSettings` holds speed and highlight mode, persisted through one key registry.

### 3.4 `ReadAloudNavigator` (305 code lines, 19 stored properties)

| Responsibility | State | Functions (line ranges in ReadAloudNavigator.swift) |
| --- | --- | --- |
| Listening queue | `queue`, `history`, `startReading`, `vaultRoot` | `playNext`, `addToQueue`, `removeFromQueue`, `advance`, `goToPreviousItem`, `vaultPath(ofSource:)` (286-327) |
| Remembered places (UserDefaults) | `preferences`; keys `positionsKey`, `positionsOrderKey` | three `rememberedLocation` overloads, `forgetLocation`, `remember` (330-370) |
| Moving within the reading | `resumedFromRememberedPlace`, `visibleLocation`, `visiblePageIndex` | `read(fromSourceLocation:)`, `readFromVisiblePosition`, `backToReading`, `sections`, `currentSectionIndex`, `canSkipSection`, `skipSection`, `jump`, `resumeWhenPrepared`, `stopAndRewind`, `startOver` (74-185) |
| Range taps | `rangeSelection`, `supportsTapToRead` | `beginRangeSelection`, `cancelRangeSelection`, `tapped` (189-207) |
| Read Aloud pen | `penStart`, `penEnd`, `replayPenRange` | `penTapped`, `readingPenRange`, `penMarks`, `isReadingPenSelection`, `clearPenMarks` (212-282) |
| Layout frames for the player | `highlightFrameInWindow`, `windowBounds`, `coveredFrameInWindow`, `playerFrameInWindow` | none |
| Repeat and end of reading | `repeatsPassage` | `observeReading`, `readingChanged` (374-407) |

**Coupling.**
- `readingChanged` persists places, replays the pen range, repeats the passage and advances the queue in one function ([ReadAloudNavigator.swift:387-407](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L387-L407)).
- `init` writes the static `ReadAloudNowPlaying.queueCommands` ([ReadAloudNavigator.swift:62-68](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L62-L68)).

**Rules.** `observeReading` re-arms observation after every change ([ReadAloudNavigator.swift:374-385](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L374-L385)). A place is remembered before the end-of-reading decision.

**Verdict and split.**
- `ListeningQueue`.
- `RememberedReadingPlaces` over an injected key-value store.
- `ReadAloudPenSelection`.
- `ReadAloudLayoutFrames`, a plain observable value owned by the floating player.
- Sentence and section moves join the single transport that also owns Stop (section 7).

### 3.5 `ReadAloudPassagePreparation` (18 stored properties) and `NeuralReadAloudSpeech` (14)

`ReadAloudPassagePreparation` ([ReadAloudPassagePreparation.swift:59-83](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L59-L83), [ReadAloudPassagePreparation.swift:260](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L260)):

- **Observable status:** `preparedShare`, `isPreparing`, `failureMessage`, `isSuspended`, `systemVoiceTexts`, `lastRejection`.
- **Dependencies:** `cache`, `renderer`, `aligner`.
- **Queue state:** `voice`, `language`, `queue`, `readyTexts`, `passageTexts`, `writtenTexts`, `fallbackVoice`, `worker`, `waiters`.
- **Jobs:** scheduling (`prepare`, `startWorker`, `suspend`, `resumeAfterSuspension`, `cancel`, `waitForPassage`, `nextUnrenderedText`, `finish`), render policy (`renderChecked`, `renderWithRetry`) and waiter fan-out.

Rules:
1. `cancel` resumes every waiter with nil ([ReadAloudPassagePreparation.swift:163](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L163)).
2. `waitForPassage` can call `prepare`, which calls `cancel` and so ends other waiters ([ReadAloudPassagePreparation.swift:178-183](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L178-L183), [ReadAloudPassagePreparation.swift:121](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L121)).
3. The model is freed only when the queue ends without cancellation ([ReadAloudPassagePreparation.swift:213-220](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L213-L220)).

Split:
- `PassageRenderQueue`, a value holding the queue, the ready set, the waiters and the prepared share;
- `CheckedPassageRenderer` for the attempts, checks, fallback and logging;
- a thin observable status.

`NeuralReadAloudSpeech` ([NeuralReadAloudSpeech.swift:17-35](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L17-L35)) does five jobs:
- mode routing (`quick`, `routesToQuick`);
- pre-render pass-through (`prepareAhead`, `cancelPreparation`, `setLanguage`);
- playback (`player`, `activeRequest`, `playingPassage`, `pendingStart`);
- the word clock (`wordTimer`, `lastReportedWordLocation`);
- audio-session ownership and interruptions (`ownsActiveAudioSession`, the observer at lines 46-50).

The audio-session job duplicates `AppleReadAloudSpeech` (CC-VOICE-07). The split keeps routing and playback here and moves the audio session to one shared owner.

### 3.6 `ReadAloudFloatingPlayer` (303 code lines in one view)

- It computes its status with an 8-branch `if` chain ([ReadAloudFloatingPlayer.swift:100-140](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L100-L140)).
- It schedules sleeps ([ReadAloudFloatingPlayer.swift:59-62](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L59-L62), [ReadAloudFloatingPlayer.swift:352-357](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L352-L357)).
- It writes the navigator's frames from a geometry callback ([ReadAloudFloatingPlayer.swift:88-91](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L88-L91)).
- It calls the session directly on 15 lines (grep `reader\.session\.` in the file).

Split:
- `ReadAloudPlayerStatus`, an enum computed by a pure function of controller and navigator state (range prompt, error, scrolled away, preparing, pen selection, title); the view switches over it;
- `ReadAloudPageMenu`, the 60-line menu as its own view;
- transport actions as calls on the single transport.

## 4. Findings by principle

### S

#### SRP-VOICE-01 `ReadAloudController` is the reader for every source and every concern of reading
- **Severity:** High
- **Evidence:**
  - 39 stored properties ([ReadAloudController.swift:29-82](../../../Sources/GraphiteUI/ReadAloudController.swift#L29-L82), [ReadAloudController.swift:553](../../../Sources/GraphiteUI/ReadAloudController.swift#L553)), counted by reading, in the 8 groups of section 3.1.
  - Three hand-written reset lists that disagree:

    | Reset list | Fields reset | Location |
    | --- | ---: | --- |
    | `begin` | 26 | [ReadAloudController.swift:591-625](../../../Sources/GraphiteUI/ReadAloudController.swift#L591-L625) |
    | `clear` | 17 | [ReadAloudController.swift:424-443](../../../Sources/GraphiteUI/ReadAloudController.swift#L424-L443) |
    | `documentDidChange` | 6 | [ReadAloudController.swift:402-412](../../../Sources/GraphiteUI/ReadAloudController.swift#L402-L412) |

    `clear` leaves `pdfRunningText`, `title`, `scopeDescription` and `sourceHighlightNotice` as they were. `stop` resets neither `foldPreparationIdentifier` nor `noteReanchoring` ([ReadAloudController.swift:414-422](../../../Sources/GraphiteUI/ReadAloudController.swift#L414-L422)).
  - The file was touched by 15 of 242 commits (reconnaissance), the most in the area.
- **Why it matters:**
  - Every new field must be added to three reset lists from memory.
  - The gaps cause BUG-VOICE-01 and BUG-VOICE-02.
  - No unit can be tested without a `PDFSession`, a session and a preference store.
- **Fix direction:** split into `MarkdownReading`, `PDFReading` (with a state enum), `ScannedPageReview` and `FollowReadingPolicy`. The controller then holds one optional active reading, so a reset is replacing that value (section 3.1).

#### SRP-VOICE-02 `ReadAloudDocument.markdown` and `pageText` each do several jobs through shared mutable locals
- **Severity:** High
- **Evidence:**
  - `markdown` spans [ReadAloudDocument.swift:296-589](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L296-L589) (273 code lines). It has 4 nested functions (`mask`, `flush`, `appendUnmapped`, `append`). Character mapping sits 4 control levels deep inside it ([ReadAloudDocument.swift:517-584](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L517-L584)).
  - `pageText` spans [ReadAloudDocument.swift:79-237](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L79-L237) (149 code lines) with 5 nested functions.
  - Besides the reader, the reading view and Live Preview use the builder for token mapping ([MarkdownPreview.swift:318](../../../Sources/GraphiteUI/MarkdownPreview.swift#L318), [LivePreviewWidgets.swift:148](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L148)).
- **Why it matters:** fixing one Markdown construct (tables, callouts, entities) means editing a 273-line function that also decides highlight geometry in two other views. Tests can only pin whole documents.
- **Fix direction:** extract the pieces listed in section 3.2 (masking, leaf walk, assembler, run mapper, PDF lines, running text, hyphenation) into separately tested Core types. `ReadAloudDocument` keeps the values and the entry points.

#### SRP-VOICE-03 `ReadAloudSession` mixes playback, voice catalogue, highlight projection and preference storage
- **Severity:** Medium
- **Evidence:**
  - 24 stored properties in 5 groups (section 3.3).
  - Voice resolution and user messages sit inside the playback step ([ReadAloudSpeech.swift:712-721](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L712-L721)).
  - `init` migrates old preference keys ([ReadAloudSpeech.swift:456](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L456)).
  - The type also produces settings-path text for the UI ([ReadAloudSpeech.swift:532-543](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L532-L543)).
- **Why it matters:** the two voice-sample sessions ([ReadAloudVoiceSettings.swift:14](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L14), [ReadAloudPronunciationEditor.swift:13](../../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L13)) each carry a full playback machine, a preference migration and an `AVSpeechSynthesizer` to play one sentence.
- **Fix direction:** split into `ReadAloudPlayback` (state enum), `ReadAloudVoiceSelection`, `ReadAloudHighlightProjection` (pure) and `ReadAloudSpeechSettings`, as in section 3.3.

#### SRP-VOICE-04 `ReadAloudNavigator` combines queue, persistence, pen, range taps and layout frames
- **Severity:** Medium
- **Evidence:**
  - 19 stored properties in 7 groups (section 3.4).
  - `readingChanged` writes `UserDefaults`, replays the pen range, repeats the passage and advances the queue ([ReadAloudNavigator.swift:387-407](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L387-L407)).
  - It holds four window frames that views write ([ReadAloudNavigator.swift:46-52](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L46-L52)).
  - The file also contains a SwiftUI view ([ReadAloudNavigator.swift:410-423](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L410-L423)).
- **Why it matters:**
  - The type has no test (grep `ReadAloudNavigator` over `Tests/**` returns nothing).
  - Observation tracking is per property, so frame writes do not re-render observers of the queue. But every frame write runs through the same observable object that owns the queue and the persisted places.
- **Fix direction:** `ListeningQueue`, `RememberedReadingPlaces` (injected store), `ReadAloudPenSelection` and `ReadAloudLayoutFrames`. Sentence and section moves go to the transport.

#### SRP-VOICE-05 `ReadAloudPassagePreparation` is scheduler, render-retry policy and status in one observable object
- **Severity:** Medium
- **Evidence:**
  - 18 stored properties (section 3.5).
  - The retry and fallback policy and its logging live inside `renderChecked` ([ReadAloudPassagePreparation.swift:228-257](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L228-L257)), next to queue reordering ([ReadAloudPassagePreparation.swift:174-190](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L174-L190)).
- **Why it matters:** the scheduling rules (deduplication by suffix, reordering, waiter fan-out) have no test. A change to the retry policy risks the waiter bookkeeping.
- **Fix direction:** a `PassageRenderQueue` value with pure transitions (testable without MLX), a `CheckedPassageRenderer` built from the injected renderer and aligner, and a thin observable status.

### O

#### OCP-VOICE-01 A new neural model family is wired in 7 places across 3 files
- **Severity:** Medium
- **Evidence:** counted by reading:

  | # | Place | Kind |
  | ---: | --- | --- |
  | 1 | Model construction ([NeuralSpeechEngine.swift:95-104](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L95-L104)) | exhaustive switch |
  | 2 | Generation parameters ([NeuralSpeechEngine.swift:194-207](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L194-L207)) | exhaustive switch |
  | 3 | Sample generation, including Dia's `"[S1] "` prefix ([NeuralSpeechEngine.swift:222-246](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L222-L246)) | exhaustive switch |
  | 4 | Sentence-group rule ([NeuralSpeechEngine.swift:126](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L126)) | `== .pocketTTS` |
  | 5 | Acronym rule ([NeuralVoiceManifest.swift:18](../../../Sources/GraphiteCore/NeuralVoiceManifest.swift#L18)) | `!= .pocketTTS` |
  | 6 | Fallback voice ([NeuralVoiceLibrary.swift:117](../../../Sources/GraphiteVoices/NeuralVoiceLibrary.swift#L117)) | `== .pocketTTS` |
  | 7 | Dia codec folder ([NeuralSpeechEngine.swift:109](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L109)) | constant |

- **Why it matters:** the compiler flags the three switches; the three equality tests are silent. A new family therefore defaults to "writes acronyms", "split into sentence groups" and "never a fallback" without anyone deciding.
- **Fix direction:** one descriptor per `NeuralVoiceModelFamily` case (loader, parameters, splitting, acronym policy, fallback rank), declared in one place and reached through one exhaustive switch.

#### OCP-VOICE-02 Voice-quality groups and platform names are display strings used as identities
- **Severity:** Low
- **Evidence:**
  - The settings picker groups voices by `qualityDescription` strings ([ReadAloudVoiceSettings.swift:120-122](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L120-L122)), produced in the Apple layer ([ReadAloudSpeech.swift:46-54](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L46-L54)).
  - Platforms are the strings `"iOS"` and `"macOS"` in the manifest and the library ([NeuralVoiceManifest.swift:94](../../../Sources/GraphiteCore/NeuralVoiceManifest.swift#L94), [NeuralVoiceLibrary.swift:34-40](../../../Sources/GraphiteVoices/NeuralVoiceLibrary.swift#L34-L40), [NeuralVoiceLibrary.swift:84-86](../../../Sources/GraphiteVoices/NeuralVoiceLibrary.swift#L84-L86)).
- **Why it matters:** renaming "Default" in the UI changes the grouping, and a typo in the manifest's platform list hides a voice silently.
- **Fix direction:**
  - a `ReadAloudVoiceTier` enum (personal, premium, enhanced, standard, classic), mapped to words in the view;
  - a `NeuralVoicePlatform` enum decoded at the manifest boundary, with an `unknown(String)` case.

### L

#### LSP-VOICE-01 The system-voice and neural adapters honour different contracts for the same `ReadAloudSpeaking` calls
- **Severity:** High
- **Evidence:** compared by reading both adapters.

  | Contract point | `AppleReadAloudSpeech` | `NeuralReadAloudSpeech` (High Quality) |
  | --- | --- | --- |
  | `voiceIdentifier` | Speaks that voice; throws when it is missing ([ReadAloudSpeech.swift:248-250](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L248-L250)) | Ignored; reads `library.selectedVoice` ([NeuralReadAloudSpeech.swift:73-78](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L73-L78)) |
  | `speed` | 0.5–3× mapped onto the synthesizer rate ([ReadAloudSpeech.swift:311-316](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L311-L316)) | Clamped to 0.5–1.5× ([RenderedPassagePlayer.swift:39](../../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L39)) |
  | `usesSystemSettings` | Sets `prefersAssistiveTechnologySettings` ([ReadAloudSpeech.swift:272](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L272)) | Ignored |
  | `assistiveSpeechSettingsMayApply` | True under VoiceOver, Speak Selection or Speak Screen, when the system rate does apply ([ReadAloudSpeech.swift:206-212](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L206-L212)) | Forwards the same answer ([NeuralReadAloudSpeech.swift:59](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L59)), although nothing applies the system rate to rendered audio |
  | `phoneticRanges` | Applied as IPA attributes ([ReadAloudSpeech.swift:257-261](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L257-L261)) | Ignored; uses `request.passage` |
  | Route change, media-services reset | Pause and `.interrupted` ([ReadAloudSpeech.swift:171-173](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L171-L173), [ReadAloudSpeech.swift:375-390](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L375-L390)) | Not observed; only interruptions ([NeuralReadAloudSpeech.swift:46-50](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L46-L50)) |
  | `.paused`, `.continued`, `.cancelled` events | Asynchronous, from delegate callbacks; never `.cancelled` after its own `stop` ([ReadAloudSpeech.swift:320-358](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L320-L358)) | Synchronous inside `pause` and `resume` ([NeuralReadAloudSpeech.swift:215](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L215), [NeuralReadAloudSpeech.swift:223](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L223)); `.cancelled` when a file fails to play ([NeuralReadAloudSpeech.swift:171-174](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L171-L174)) |

- **Why it matters:**
  - The session and the UI are written against the Apple behaviour, which causes BUG-VOICE-04, -05 and -08.
  - The session requires an installed Apple voice for the passage's language before High Quality may play ([ReadAloudSpeech.swift:712-721](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L712-L721)). That check means nothing for a neural voice.
- **Fix direction:**
  - State the contract once: speed range, events, route handling, and which request fields an adapter must honour.
  - Each adapter reports capabilities (`supportedSpeedRange`, `appliesSystemSpeechSettings`) that the UI reads.
  - One contract test suite runs against both adapters (section 7).

#### LSP-VOICE-02 Protocol default implementations silently drop request fields, and the test fakes run through them
- **Severity:** Medium
- **Evidence:**
  - The default `speak(_ utterance:)` forwards without `phoneticRanges`, `passage` and `passageOffset`. The default six-parameter `speak` drops `leadingPauseSeconds` and `usesSystemSettings` ([ReadAloudSpeech.swift:135-144](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L135-L144)).
  - Eight more defaults answer "unsupported" or do nothing ([ReadAloudSpeech.swift:145-152](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L145-L152)).
  - `ControllerTestSpeech` implements 6 of the 16 requirements and inherits both speak defaults ([ReadAloudControllerTests.swift:10-18](../../../Tests/GraphiteUITests/ReadAloudControllerTests.swift#L10-L18)). `ScanHighlightSpeech` does the same ([ReadAloudScanHighlightTests.swift:9-11](../../../App/Tests/ReadAloudScanHighlightTests.swift#L9-L11)).
- **Why it matters:**
  - Controller tests exercise a speech path that production never takes: both adapters implement `speak(_ request:)` ([ReadAloudSpeech.swift:245](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L245), [NeuralReadAloudSpeech.swift:71](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L71)).
  - A new adapter that forgets one method still compiles, and loses pauses or resume offsets.
- **Fix direction:**
  - One required `speak(_ request: ReadAloudUtteranceRequest, requestIdentifier:)`, with no forwarding overloads.
  - Optional capabilities move to separate protocols (ISP-VOICE-01).
  - One test fake lives in a test-support module and records the whole request.

#### LSP-VOICE-03 Four functions named `stop` have four scopes, and the player's two Stop buttons call different ones
- **Severity:** Medium
- **Evidence:**

  | Caller or function | What it stops | Location |
  | --- | --- | --- |
  | Floating player Stop → `ReadAloudNavigator.stopAndRewind` | The session only; preparation, fold task and PDF continuation stay alive | [ReadAloudFloatingPlayer.swift:222-225](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L222-L225), [ReadAloudNavigator.swift:174-178](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L174-L178) |
  | Popover Stop → `ReadAloudController.clear` | Everything | [ReadAloudControls.swift:208-211](../../../Sources/GraphiteUI/ReadAloudControls.swift#L208-L211) |
  | `ReadAloudController.stop` | Preparation; keeps the requests | [ReadAloudController.swift:414-422](../../../Sources/GraphiteUI/ReadAloudController.swift#L414-L422) |
  | `ReadAloudSession.stop` | Speech, and releases the audio session | [ReadAloudSpeech.swift:582-592](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L582-L592) |
  | `NeuralReadAloudSpeech.stop` | Playback and the pending start | [NeuralReadAloudSpeech.swift:227-238](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L227-L238) |

- **Why it matters:** BUG-VOICE-01 and BUG-VOICE-02.
- **Fix direction:** one transport `stop(scope:)` with an enum scope (`rewindKeepingDocument`, `endReading`) that always cancels pending preparation.

#### LSP-VOICE-04 The session's "voice without word timing" memory keys on the Apple voice even when a neural voice speaks
- **Severity:** Low
- **Evidence:**
  - The session records `speakingVoiceIdentifier = selectedVoiceIdentifier`, an Apple identifier ([ReadAloudSpeech.swift:727](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L727)).
  - It flags that identifier after 0.7 s without words ([ReadAloudSpeech.swift:817-822](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L817-L822)).
  - A neural passage whose alignment failed has `wordTimings == nil` ([ReadAloudAudioCache.swift:9-11](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L9-L11)) and sends no `.spoken` events ([NeuralReadAloudSpeech.swift:192-194](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L192-L194)).
- **Why it matters:** after one unaligned neural passage, every later passage, including system-voice passages with that Apple voice, starts with a whole-passage highlight. The highlight lasts until the first word event clears the flag ([ReadAloudSpeech.swift:782-784](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L782-L784)).
- **Fix direction:** the adapter reports, per request, whether word timing exists (an event or a capability). The session stops inferring it from an identifier the adapter ignores.

#### LSP-VOICE-05 Two "word at a playback time" implementations disagree on silence
- **Severity:** Low
- **Evidence:**
  - `ReadAloudAudioTiming.wordRange(atPlaybackSeconds:)` returns nil between words ([ReadAloudAudioTiming.swift:77-90](../../../Sources/GraphiteCore/ReadAloudAudioTiming.swift#L77-L90)).
  - `ReadAloudWordAlignment.word(at:in:)` returns the last word that started ([ReadAloudWordAlignment.swift:179-187](../../../Sources/GraphiteCore/ReadAloudWordAlignment.swift#L179-L187)).
  - Production uses only the second ([NeuralReadAloudSpeech.swift:193](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L193)).
- **Why it matters:** there are two tested answers to one question. Architecture describes the unused one as the behaviour ("Playback-clock queries return no word during silence", [Architecture.md:23](../../../Docs/Architecture.md#L23)).
- **Fix direction:** keep one timing model (`ReadAloudTimedWord`). Either delete `ReadAloudAudioTiming` or make it the only one.

#### LSP-VOICE-06 On the Mac the recognized-word highlight colour does not follow appearance changes
- **Severity:** Low
- **Evidence:** UIKit assigns the dynamic `UIColor` ([PDFRecognizedReadingOverlay.swift:60](../../../Sources/GraphiteUI/PDFRecognizedReadingOverlay.swift#L60)). AppKit resolves `.cgColor` once, at creation ([PDFRecognizedReadingOverlay.swift:64](../../../Sources/GraphiteUI/PDFRecognizedReadingOverlay.swift#L64)).
- **Why it matters:** a word view created in light appearance keeps the light alpha (0.24) after a switch to dark, where the style asks for 0.4 ([ReadAloudHighlightStyle.swift:23](../../../Sources/GraphiteUI/ReadAloudHighlightStyle.swift#L23)).
- **Fix direction:** set `layer.backgroundColor` again in `viewDidChangeEffectiveAppearance`, or resolve the colour in `updateLayer`.

### I

#### ISP-VOICE-01 `ReadAloudSpeaking` has 16 requirements covering 6 concerns
- **Severity:** Medium
- **Evidence:** [ReadAloudSpeech.swift:101-133](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L101-L133), counted by reading. Ten of the 16 have defaults.

  | Concern | Requirements |
  | --- | --- |
  | Events | `eventHandler` |
  | Voice catalogue | `voices`, `systemDefaultVoiceIdentifier`, `systemVoice` |
  | Permissions and system settings | `personalVoiceStatus`, `requestPersonalVoiceAccess`, `assistiveSpeechSettingsMayApply` |
  | Playback | three `speak` overloads, `pause`, `resume`, `stop` |
  | Audio route | `releaseAudio` |
  | Ahead-of-time rendering | `prepareAhead`, `cancelPreparation` |

  `NeuralReadAloudSpeech` forwards six catalogue and permission members to the system voice ([NeuralReadAloudSpeech.swift:56-61](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L56-L61)).
- **Why it matters:** every fake must reason about 16 members, and the forwarding layer grows with each concern.
- **Fix direction:** three protocols, each with a real substitution:
  - `ReadAloudSpeechPlayback` (speak, pause, resume, stop, events, release), implemented by both adapters and the fake;
  - `ReadAloudVoiceCatalogue` (voices, system voice, Personal Voice), implemented by the Apple catalogue and a fake;
  - `AheadOfTimeRendering` (prepare, cancel), implemented by the neural adapter.

#### ISP-VOICE-02 Views take the whole controller and drive the session directly
- **Severity:** Medium
- **Evidence:**
  - 67 lines read or call `reader.session.` in `Sources/GraphiteUI/*.swift` (grep `reader\.session\.`): 15 in `ReadAloudControls.swift`, 21 in `ReadAloudNavigator.swift`, 15 in `ReadAloudFloatingPlayer.swift`, 15 in `ReadAloudReader.swift` and 1 in `MarkdownPane.swift`.
  - `ReadAloudVoiceSettings` takes the controller only for `session` and `prepareVoiceSample` ([ReadAloudVoiceSettings.swift:11](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L11), [ReadAloudVoiceSettings.swift:21](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L21), [ReadAloudVoiceSettings.swift:152](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L152)).
- **Why it matters:**
  - Views bypass controller invariants.
  - The Transcript rows start playback without the `isPreparing` guard that the Play buttons have ([ReadAloudReader.swift:87-90](../../../Sources/GraphiteUI/ReadAloudReader.swift#L87-L90), compare [ReadAloudControls.swift:59](../../../Sources/GraphiteUI/ReadAloudControls.swift#L59)).
  - Stop differs from view to view (LSP-VOICE-03).
- **Fix direction:**
  - Give views a `ReadAloudTransport` (play, pause, `stop(scope:)`, sentence and section moves, speed) and a read-only `ReadAloudStatus` projection.
  - Voice settings take `ReadAloudVoiceSelection` and a closure that prepares the sample.

#### ISP-VOICE-03 The vault pronunciation file is decoded as untyped dictionaries and written through a narrower type
- **Severity:** Medium
- **Evidence:**
  - Reading uses `JSONSerialization` to `[String: Any]` and `fields["say"] as? String` ([ReadAloudPronunciations.swift:64](../../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L64), [ReadAloudPronunciations.swift:71-72](../../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L71-L72)).
  - Writing goes through `[String: String]`, which has no place for `ipa` ([ReadAloudPronunciations.swift:80-88](../../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L80-L88)).
- **Why it matters:** the Settings editor rewrites the user's vault file with less information (BUG-VOICE-10).
- **Fix direction:** a `Codable` entry enum (`respelling(String)` or `detailed(say:ipa:)`) used for both reading and writing, with a golden round-trip test.

### D

#### DIP-VOICE-01 A static service locator holds the voice library and the render queue
- **Severity:** Medium
- **Evidence:**
  - `static let library` and `static let preparation` ([ReadAloudVoices.swift:15-17](../../../Sources/GraphiteUI/ReadAloudVoices.swift#L15-L17)), with 11 references (grep `ReadAloudVoices\.(preparation|library)`).
  - Views cancel the shared queue directly ([NeuralVoiceSettings.swift:16](../../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L16), [NeuralVoiceSettings.swift:91](../../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L91)), and Settings reaches the library ([SettingsView.swift:340](../../../Sources/GraphiteUI/SettingsView.swift#L340), [SettingsView.swift:366](../../../Sources/GraphiteUI/SettingsView.swift#L366)).
  - The locator's lazy initializer registers lifecycle notifications ([ReadAloudVoices.swift:24-29](../../../Sources/GraphiteUI/ReadAloudVoices.swift#L24-L29)). `try?` hides why the manifest failed ([ReadAloudVoices.swift:15](../../../Sources/GraphiteUI/ReadAloudVoices.swift#L15)).
- **Why it matters:**
  - Views reach a background render queue that the workspace does not own.
  - A second workspace would share one queue whose `prepare` cancels the other workspace's waiters ([ReadAloudPassagePreparation.swift:121](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L121), [ReadAloudPassagePreparation.swift:163](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L163)). One workspace exists today ([GraphiteMacScenes.swift:23-28](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L23-L28)).
- **Fix direction:**
  - The composition root builds the library, the preparation and the controller, and passes them down.
  - Views call intent methods on the library (`chooseMode`, `delete`), and those methods cancel rendering themselves.

#### DIP-VOICE-02 Initializers construct I/O collaborators in default arguments
- **Severity:** Medium
- **Evidence:** 5 places, counted by reading:
  1. `ReadAloudSession(speech: AppleReadAloudSpeech(), preferences: .standard)` ([ReadAloudSpeech.swift:454](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L454))
  2. `ReadAloudController(session: ReadAloudSession(), preferences: .standard)` ([ReadAloudController.swift:84-85](../../../Sources/GraphiteUI/ReadAloudController.swift#L84-L85))
  3. `ReadAloudNavigator(preferences: .standard)` ([ReadAloudNavigator.swift:58](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L58))
  4. `ReadAloudNavigator.rememberedLocation(preferences: .standard)` ([ReadAloudNavigator.swift:344](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L344))
  5. `NeuralVoiceLibrary(preferences: .standard, physicalMemoryBytes: ProcessInfo…)` ([NeuralVoiceLibrary.swift:44-45](../../../Sources/GraphiteVoices/NeuralVoiceLibrary.swift#L44-L45))

  The controller also builds its own `ReadAloudMarkdownPreparation` ([ReadAloudController.swift:48](../../../Sources/GraphiteUI/ReadAloudController.swift#L48)) and `ReadAloudNowPlaying` ([ReadAloudController.swift:90](../../../Sources/GraphiteUI/ReadAloudController.swift#L90)).
- **Why it matters:**
  - The production factory gets `.standard` and a real synthesizer by omitting arguments ([ReadAloudVoices.swift:37-39](../../../Sources/GraphiteUI/ReadAloudVoices.swift#L37-L39)).
  - Hosted tests that build a `WorkspaceModel` read and write the person's real preferences. `ReadAloudLectureHighlightTests` saves and restores the real speed ([ReadAloudLectureHighlightTests.swift:24-25](../../../App/Tests/ReadAloudLectureHighlightTests.swift#L24-L25)).
- **Fix direction:** no defaults for speech, preferences or system probes; the composition root passes them in.

#### DIP-VOICE-03 A static mutable hook connects remote commands to the listening queue
- **Severity:** Low
- **Evidence:**
  - `static var queueCommands` ([ReadAloudNowPlaying.swift:21](../../../Sources/GraphiteUI/ReadAloudNowPlaying.swift#L21)) is written by every navigator's `init` ([ReadAloudNavigator.swift:62-68](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L62-L68)).
  - The remote-command targets read it ([ReadAloudNowPlaying.swift:65-66](../../../Sources/GraphiteUI/ReadAloudNowPlaying.swift#L65-L66)).
- **Why it matters:** the last navigator created wins. If a second workspace ever exists, one reading's lock-screen buttons drive the other workspace's queue.
- **Fix direction:** pass the queue commands in `ReadAloudNowPlaying.Commands` from the controller's owner.

#### DIP-VOICE-04 The cache uses the wall clock and the file system directly, and its actor is untested
- **Severity:** Low
- **Evidence:**
  - `Date()` stamps last use ([ReadAloudAudioCache.swift:71](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L71), [ReadAloudAudioCache.swift:110](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L110)).
  - `FileManager.default` appears 11 times in the cache file (grep).
  - Only the pure eviction is tested ([NeuralReadAloudTests.swift:90-106](../../../Tests/GraphiteCoreTests/NeuralReadAloudTests.swift#L90-L106)).
- **Why it matters:** the actor's LRU stamping, index persistence and orphan handling (CC-VOICE-11) have no test.
- **Fix direction:**
  - Inject a clock into `ReadAloudAudioCache`.
  - The folder is already injectable ([ReadAloudAudioCache.swift:40](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L40)); add actor tests on a temporary folder.

#### DIP-VOICE-05 The measuring tool ships in the production module and the app entry point
- **Severity:** Low
- **Evidence:**
  - `NeuralVoiceBenchmark` and `ProcessResources` live in `GraphiteVoices` ([NeuralVoiceBenchmark.swift:82](../../../Sources/GraphiteVoices/NeuralVoiceBenchmark.swift#L82), [ProcessResources.swift:5](../../../Sources/GraphiteVoices/ProcessResources.swift#L5)).
  - The app's root scene checks the launch argument ([GraphiteApp.swift:24](../../../App/GraphiteApp.swift#L24)).
  - The screen disables the idle timer and plays looping silence ([NeuralVoiceBenchmarkScreen.swift:33](../../../Sources/GraphiteUI/NeuralVoiceBenchmarkScreen.swift#L33), [NeuralVoiceBenchmarkScreen.swift:53-62](../../../Sources/GraphiteUI/NeuralVoiceBenchmarkScreen.swift#L53-L62)).
- **Why it matters:** device-measurement code and its launch switch ship to users. `PCMWaveFile` in Core exists only for it: grep `PCMWaveFile` in `Sources/**` matches only the benchmark and its screen.
- **Fix direction:** a separate benchmark target, or a build configuration excluded from release, with `PCMWaveFile` moved beside it.

### Clean code

#### CC-VOICE-01 Nineteen functions exceed 40 code lines; two exceed 140
- **Severity:** Medium
- **Evidence:** the reconnaissance lists 19 (section 8). I checked the spans of the largest by reading:
  - `ReadAloudDocument.markdown`, 273 code lines ([ReadAloudDocument.swift:296-589](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L296-L589))
  - `ReadAloudDocument.pageText`, 149 ([ReadAloudDocument.swift:79-237](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L79-L237))
  - `ReadAloudScanReview.body`, 75 ([ReadAloudReader.swift:177-251](../../../Sources/GraphiteUI/ReadAloudReader.swift#L177-L251))
  - `ReadAloudController.preparePDFSnapshot`, 59 ([ReadAloudController.swift:657-720](../../../Sources/GraphiteUI/ReadAloudController.swift#L657-L720))
  - `ReadAloudSession.receive`, 49 ([ReadAloudSpeech.swift:753-807](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L753-L807))

  `preparePDFSnapshot` takes 9 parameters ([ReadAloudController.swift:657-659](../../../Sources/GraphiteUI/ReadAloudController.swift#L657-L659)) and `loadPDFPage` 5.
- **Why it matters:** these functions hold the highest-risk logic: source mapping, the page pipeline, event handling. They cannot be reviewed or tested in parts.
- **Fix direction:** the splits in sections 3.1–3.3. `preparePDFSnapshot` takes a `PDFPageRequest` value instead of 9 parameters.

#### CC-VOICE-02 A sleep-poll loop waits for another object's preparation
- **Severity:** Medium
- **Evidence:** `resumeWhenPrepared` checks `reader.isPreparing` up to 200 times, 50 ms apart, then acts whatever the state ([ReadAloudNavigator.swift:153-167](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L153-L167)). Both note-opening paths call it ([WorkspaceModel.swift:1463](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1463), [MarkdownPane.swift:570](../../../Sources/GraphiteUI/MarkdownPane.swift#L570)). Controller tests poll the same flag every 5 ms ([ReadAloudControllerTests.swift:32-36](../../../Tests/GraphiteUITests/ReadAloudControllerTests.swift#L32-L36)).
- **Why it matters:** two failure cases:
  - A note that takes more than 10 s to prepare (first math-interpreter load on a large note) is resumed at the start.
  - The task has no owner: when another reading begins inside the window, the remembered place of the old note is applied to the new one. The only guard is `session.document != nil` ([ReadAloudNavigator.swift:161](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L161)).
- **Fix direction:** pass the resume location into the Markdown reading request, like `pendingPosition` for PDFs ([ReadAloudController.swift:730-736](../../../Sources/GraphiteUI/ReadAloudController.swift#L730-L736)). Preparation then applies it as part of finishing.

#### CC-VOICE-03 Sleeps order UI events, and tasks run without an owner
- **Severity:** Medium
- **Evidence:** 9 `Task.sleep` calls in the area (grep over the area's files).
  - Sleeps used for ordering:
    - 450 ms between dismissing the popover and showing the sheet ([ReadAloudControls.swift:202-205](../../../Sources/GraphiteUI/ReadAloudControls.swift#L202-L205));
    - 250 ms after a chip tap ([ReadAloudFloatingPlayer.swift:352-357](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L352-L357));
    - a 5 s hint timer ([ReadAloudFloatingPlayer.swift:59-62](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L59-L62)).
  - Tasks without an owner:
    - the fold re-preparation ([ReadAloudController.swift:136](../../../Sources/GraphiteUI/ReadAloudController.swift#L136));
    - the Now Playing and navigator observation re-arming ([ReadAloudController.swift:472](../../../Sources/GraphiteUI/ReadAloudController.swift#L472), [ReadAloudNavigator.swift:380](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L380));
    - `NeuralVoiceLibrary`'s cache-size refresh at init ([NeuralVoiceLibrary.swift:61](../../../Sources/GraphiteVoices/NeuralVoiceLibrary.swift#L61)).
  - Six delegate callbacks each hop to the main actor in a separate `Task` ([ReadAloudSpeech.swift:335-358](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L335-L358)). The order of word and finish events then rests on task scheduling, not on a serial queue.
- **Why it matters:**
  - The fold task cannot be cancelled, which is the cause of BUG-VOICE-02.
  - Fixed delays break when the system's animation timing changes.
- **Fix direction:**
  - Give every task an owner that cancels it (controller, view `.task`).
  - Replace the dismiss-then-present sleep with presentation completion (`onDismiss`).
  - Deliver synthesizer callbacks through one `AsyncStream`, which preserves their order.

#### CC-VOICE-04 Getters, predicates and view initializers have side effects
- **Severity:** Medium
- **Evidence:**
  - `ReadAloudSession.voices` writes three observed fields on first access ([ReadAloudSpeech.swift:421-424](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L421-L424), [ReadAloudSpeech.swift:486-490](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L486-L490)). `selectedVoice` reaches it, and `selectedVoice` is read inside a view body ([ReadAloudControls.swift:231](../../../Sources/GraphiteUI/ReadAloudControls.swift#L231)).
  - `ReadAloudAudioCache.passage(for:)` rewrites the whole `index.json` on every lookup ([ReadAloudAudioCache.swift:71-72](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L71-L72), [ReadAloudAudioCache.swift:141-144](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L141-L144)). It is called for each passage started and each queued item ([ReadAloudPassagePreparation.swift:169](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L169), [ReadAloudPassagePreparation.swift:175](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L175), [ReadAloudPassagePreparation.swift:196](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L196)).
  - The predicate `isRunningHeaderOrFooter` appends to `runningText` ([ReadAloudDocument.swift:117-131](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L117-L131)).
  - Two `@State` initial values construct a `ReadAloudSession` ([ReadAloudVoiceSettings.swift:14](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L14), [ReadAloudPronunciationEditor.swift:13](../../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L13)). The expression runs every time the view value is created. Each run builds an `AVSpeechSynthesizer` ([ReadAloudSpeech.swift:158](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L158)), registers notification observers on iOS ([ReadAloudSpeech.swift:171-173](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L171-L173)) and deletes preference keys ([ReadAloudSpeech.swift:456](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L456)).
- **Why it matters:**
  - Writing observed state during `body` evaluation schedules another update.
  - Each passage start writes a file.
  - Each parent re-render builds a throw-away synthesizer.
- **Fix direction:**
  - List voices in an explicit `refreshVoices()` called from `.task`.
  - Batch index saves (dirty flag plus save on commit, eviction or suspension).
  - `RunningTextFilter` returns its findings as values.
  - Create the sample session lazily in `.task` or pass it in.

#### CC-VOICE-05 Fifteen persisted preference keys and one suite name live in 8 files under two naming styles
- **Severity:** Medium
- **Evidence:** found with grep `Key = "|forKey: "|AppStorage\("|suiteName: "`.

  | Key | Declared at |
  | --- | --- |
  | `GraphiteReadAloudVoiceChoice`, `GraphiteReadAloudHighlightMode`, `GraphiteReadAloudSpeed`, abandoned `GraphiteReadAloudVoice`, `GraphiteReadAloudChosenVoice` | [ReadAloudSpeech.swift:444-452](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L444-L452) |
  | `GraphiteReadAloudPositions`, `GraphiteReadAloudPositionsOrder` | [ReadAloudNavigator.swift:53-56](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L53-L56) |
  | `GraphiteReadAloudPlayerCorner`, `GraphiteReadAloudTapHintShown` | [ReadAloudFloatingPlayer.swift:22-24](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L22-L24) |
  | `readAloudMathematicalStyle`, `readAloudPDFReadingOrder` (inline literals, each used twice) | [ReadAloudController.swift:91-92](../../../Sources/GraphiteUI/ReadAloudController.swift#L91-L92), [ReadAloudController.swift:154](../../../Sources/GraphiteUI/ReadAloudController.swift#L154), [ReadAloudController.swift:169](../../../Sources/GraphiteUI/ReadAloudController.swift#L169) |
  | `GraphiteReadAloudNeuralVoice`, `GraphiteReadAloudQualityMode`, `GraphiteReadAloudReadsUnpreparedPassagesQuickly` | [NeuralVoiceLibrary.swift:30-32](../../../Sources/GraphiteVoices/NeuralVoiceLibrary.swift#L30-L32) |
  | `GraphiteReadAloudFloatingPlayer` | [SettingsView.swift:582](../../../Sources/GraphiteUI/SettingsView.swift#L582) |
  | Suite `com.graphite.study.readAloudSample` (twice) | [ReadAloudVoiceSettings.swift:14](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L14), [ReadAloudPronunciationEditor.swift:13](../../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L13) |

- **Why it matters:**
  - A rename or a typo silently resets a person's settings.
  - The two styles (`readAloud…` against `GraphiteReadAloud…`) show that no one owns the key list.
  - The "Reset Read Aloud" and "plugin off" paths cannot enumerate what to clear.
- **Fix direction:** one `ReadAloudPreferenceKey` enum whose raw values are today's strings, used by every reader and writer, with a test that pins the raw values.

#### CC-VOICE-06 Seven members are dead or test-only in production code
- **Severity:** Low
- **Evidence:** each found with grep over `Sources/**`:

  | Member | Status |
  | --- | --- |
  | `stopIdentifier` ([ReadAloudController.swift:34](../../../Sources/GraphiteUI/ReadAloudController.swift#L34), [ReadAloudController.swift:415](../../../Sources/GraphiteUI/ReadAloudController.swift#L415)) | written, never read |
  | `setPlaybackRate` ([NeuralReadAloudSpeech.swift:241-243](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L241-L243)) | no caller |
  | `systemVoiceTexts` ([ReadAloudPassagePreparation.swift:78](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L78), [ReadAloudPassagePreparation.swift:203](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L203)) | written, never read |
  | `lastRejection` ([ReadAloudPassagePreparation.swift:252](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L252), [ReadAloudPassagePreparation.swift:260](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L260)) | documented "for tests", but no test reads it |
  | `ReadAloudAudioCache.contains` ([ReadAloudAudioCache.swift:58-60](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L58-L60)) | no caller |
  | `ReadAloudAudioCacheKey.init(fileName:)` ([ReadAloudAudioCachePolicy.swift:26-30](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L26-L30)) | tests only |
  | `ReadAloudAudioTiming` (whole type) | tests only |

- **Why it matters:** readers trust that `systemVoiceTexts` routes passages to the system voice (Architecture says so); it does not.
- **Fix direction:** delete them, or wire `systemVoiceTexts` into the queue so a passage rejected by every attempt is not rendered again (CC-VOICE-14).

#### CC-VOICE-07 Two adapters each own the one shared audio session
- **Severity:** Medium
- **Evidence:**
  - Activation and release are duplicated, each with its own `ownsActiveAudioSession` flag ([ReadAloudSpeech.swift:281-305](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L281-L305), [NeuralReadAloudSpeech.swift:245-270](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L245-L270)).
  - The neural adapter's `releaseAudio` also calls the system adapter's ([NeuralReadAloudSpeech.swift:246](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L246)).
  - Both observe interruption notifications ([ReadAloudSpeech.swift:171](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L171), [NeuralReadAloudSpeech.swift:46](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L46)).
- **Why it matters:**
  - The rule "never deactivate a recording's session" is written twice.
  - The two flags can disagree: one adapter activates, the other releases.
  - Route-change handling exists in one copy only (LSP-VOICE-01).
- **Fix direction:** one `ReadAloudAudioSessionOwner` (activate, release, interruption and route events as one stream) injected into both adapters.

#### CC-VOICE-08 Thresholds and durations are literals, some duplicated
- **Severity:** Low
- **Evidence:** counted by reading.
  - Duplicated values:
    - the 1.5 rate cap appears twice ([RenderedPassagePlayer.swift:39](../../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L39), [RenderedPassagePlayer.swift:66](../../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L66));
    - the 0.85 recognition-confidence cut appears twice ([ReadAloudReader.swift:172](../../../Sources/GraphiteUI/ReadAloudReader.swift#L172), [ReadAloudReader.swift:204](../../../Sources/GraphiteUI/ReadAloudReader.swift#L204));
    - the 256-unit correction limit appears in Apple and UI code ([PDFReadAloudPage.swift:75](../../../Sources/GraphiteApple/PDFReadAloudPage.swift#L75), [ReadAloudReader.swift:244](../../../Sources/GraphiteUI/ReadAloudReader.swift#L244)).
  - Unnamed literals:
    - 0.7 s word-timing wait ([ReadAloudSpeech.swift:818](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L818));
    - 400 ms edit debounce ([ReadAloudController.swift:362](../../../Sources/GraphiteUI/ReadAloudController.swift#L362));
    - 8 remembered running texts ([ReadAloudController.swift:688](../../../Sources/GraphiteUI/ReadAloudController.swift#L688));
    - 90- and 60-character running-text limits ([ReadAloudDocument.swift:119](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L119), [ReadAloudDocument.swift:136](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L136));
    - 0.8 page-match share and the 200,000-unit diff cap ([PDFReadAloudSource.swift:87](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L87), [PDFReadAloudSource.swift:106](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L106));
    - 2 s leading-pause cap, twice ([ReadAloudSpeech.swift:268](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L268), [NeuralReadAloudSpeech.swift:165](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L165)).
  - Counter-example: Core names its render-check thresholds ([ReadAloudRenderCheck.swift:32-39](../../../Sources/GraphiteCore/ReadAloudRenderCheck.swift#L32-L39)).
- **Why it matters:** the two leading-pause caps and the two correction limits must change together, and nothing ties them.
- **Fix direction:** named constants with units, each declared once and shared by both sides.

#### CC-VOICE-09 Comments narrate history instead of stating the rule
- **Severity:** Low
- **Evidence:** 8 comments, found by reading:
  - "measured 2026-10-16" ([ReadAloudSpeech.swift:418-420](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L418-L420))
  - "Earlier builds stored automatic picks … the owner's iPad kept … Eddy" ([ReadAloudSpeech.swift:448-450](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L448-L450))
  - "seen in the simulator, 2026-10-13" ([PDFReadAloudSource.swift:254-259](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L254-L259))
  - "the owner's papers showed no word highlight at all" ([PDFReadAloudSource.swift:76-82](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L76-L82))
  - "The places were dropped in alphabetical order" ([ReadAloudNavigator.swift:355-356](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L355-L356))
  - "PDFs were left out of the history" ([ReadAloudNavigator.swift:320](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L320))
  - "Before, one apostrophe left a whole paragraph unlit" ([ReadingSourceAlignment.swift:9](../../../Sources/GraphiteUI/ReadingSourceAlignment.swift#L9))
  - "mined on 2026-10-12 from 1,242 notes" ([ReadAloudPronunciationTerms.swift:4-5](../../../Sources/GraphiteCore/ReadAloudPronunciationTerms.swift#L4-L5))
- **Why it matters:** the history goes stale while the code changes; the rule a reader needs is buried in the story.
- **Fix direction:** keep the present-tense rule in the comment and move the incident to the commit message or a regression-test name.

#### CC-VOICE-10 Core, Apple and Voices code produces user-visible English, often with raw error text appended
- **Severity:** Medium
- **Evidence:**
  - User-facing text in lower layers:
    - `ReadAloudError.errorDescription` in Core ([ReadAloudDocument.swift:716-725](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L716-L725));
    - notice sentences built in Core ([ReadAloudDocument.swift:150](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L150), [ReadAloudDocument.swift:359](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L359), [ReadAloudDocument.swift:372](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L372), [ReadAloudDocument.swift:405](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L405));
    - layout notices in the Apple extraction actor ([PDFReadAloudPage.swift:171](../../../Sources/GraphiteApple/PDFReadAloudPage.swift#L171), [PDFReadAloudPage.swift:178](../../../Sources/GraphiteApple/PDFReadAloudPage.swift#L178), [PDFReadAloudPage.swift:237](../../../Sources/GraphiteApple/PDFReadAloudPage.swift#L237), [PDFReadAloudPage.swift:332-333](../../../Sources/GraphiteApple/PDFReadAloudPage.swift#L332-L333)).
  - Messages built from `error.localizedDescription`:
    - downloader failures ([NeuralVoiceDownloader.swift:143](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L143), [NeuralVoiceDownloader.swift:174](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L174), [NeuralVoiceDownloader.swift:290](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L290));
    - the preparation failure ([ReadAloudPassagePreparation.swift:209](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L209));
    - the controller's error message ([ReadAloudController.swift:747](../../../Sources/GraphiteUI/ReadAloudController.swift#L747)).
- **Why it matters:**
  - Notices are compared and sorted as strings ([ReadAloudDocument.swift:236](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L236)).
  - Nothing can be localised.
  - MLX and Foundation error text reaches the person unfiltered.
- **Fix direction:**
  - Core returns typed notices (`ReadAloudNotice.skippedHeadersAndFooters`, `.unsupportedEquation`, …) and typed errors.
  - One presenter in the UI turns them into words.

#### CC-VOICE-11 Failures are swallowed where the person or the cache's size limit depends on them
- **Severity:** Medium
- **Evidence:**
  - Re-preparation `try?` drops the error:
    - after a fold change, reading continues on the old document with no message ([ReadAloudController.swift:137-140](../../../Sources/GraphiteUI/ReadAloudController.swift#L137-L140));
    - after an edit, `isReanchoringNote` is cleared with no message ([ReadAloudController.swift:384-391](../../../Sources/GraphiteUI/ReadAloudController.swift#L384-L391)).
  - The cache loses track of files:
    - An unreadable `index.json` becomes an empty index while the audio files stay on disk ([ReadAloudAudioCache.swift:44-46](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L44-L46)). Eviction only counts indexed entries ([ReadAloudAudioCache.swift:133-139](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L133-L139)), so those files are never evicted.
    - A passage whose details file is missing loses its entry but keeps its audio file ([ReadAloudAudioCache.swift:64-69](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L64-L69)).
    - Index saves use `try?` ([ReadAloudAudioCache.swift:142-143](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L142-L143)).
  - A missing or malformed manifest disables High Quality without a reason ([ReadAloudVoices.swift:15](../../../Sources/GraphiteUI/ReadAloudVoices.swift#L15)).
- **Why it matters:** the 250 MiB limit is not a bound on disk use after one bad index. Edits that fail to prepare go unexplained.
- **Fix direction:**
  - The cache reconciles its index with the folder at init: unknown files are indexed or deleted, and an unreadable index is moved aside.
  - The controller shows re-preparation failures through the same typed error path as first preparation.

#### CC-VOICE-12 The playback flow is an enum plus flags and a sentinel offset
- **Severity:** Medium
- **Evidence:**
  - `State` has 4 cases ([ReadAloudSpeech.swift:397](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L397)). Beside it sit `needsRestart`, `wasSpeakingWhenInterrupted`, `lacksWordTiming` and `requestIdentifier` ([ReadAloudSpeech.swift:409](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L409), [ReadAloudSpeech.swift:433-436](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L433-L436)).
  - "Finished while paused" is encoded as `utteranceStartOffset == passage length` ([ReadAloudSpeech.swift:557](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L557), [ReadAloudSpeech.swift:796-797](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L796-L797)).
  - `prepareForVoiceOrSpeedChange`, `pause`, `receive(.interrupted)`, `receive(.cancelled)` and `seek` each set a different subset of these fields ([ReadAloudSpeech.swift:572-580](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L572-L580), [ReadAloudSpeech.swift:695-702](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L695-L702), [ReadAloudSpeech.swift:761-769](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L761-L769), [ReadAloudSpeech.swift:799-804](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L799-L804)).
- **Why it matters:** the meaning of `paused` depends on three other fields. A new transition has to reproduce the right subset by hand.
- **Fix direction:** `paused(resume: .continueUtterance | .restart(offset:) | .advanceToNextPassage)` and `speaking(request:startOffset:)`, as in section 3.3.

#### CC-VOICE-13 Heavy per-page work runs on the main actor while the person writes
- **Severity:** Medium
- **Evidence:** for every PDF page read, `preparePDFSnapshot` runs on the main actor and does three heavy things:
  1. Language recognition on the page text ([ReadAloudController.swift:667](../../../Sources/GraphiteUI/ReadAloudController.swift#L667)).
  2. Up to 400 spell-checker lookups ([ReadAloudController.swift:668-669](../../../Sources/GraphiteUI/ReadAloudController.swift#L668-L669), [ReadAloudSpelling.swift:14-26](../../../Sources/GraphiteUI/ReadAloudSpelling.swift#L14-L26)).
  3. A `difference(from:)` over up to 200,000 UTF-16 units, in a `@MainActor` function ([ReadAloudController.swift:702](../../../Sources/GraphiteUI/ReadAloudController.swift#L702), [PDFReadAloudSource.swift:75-106](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L75-L106)).

  `ReadAloudSession.load` recognises the language again on the main actor ([ReadAloudSpeech.swift:549](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L549)).
- **Why it matters:** OBJECTIVE puts the Pencil experience and editor responsiveness first. Reading a PDF while writing on it is a supported flow ([Architecture.md:42](../../../Docs/Architecture.md#L42)). A page whose exported text differs widely from the live text makes the diff approach quadratic in the number of differences on the main thread.
- **Fix direction:**
  - Run the language and diff steps in the detached worker that already builds the page document ([ReadAloudController.swift:670-682](../../../Sources/GraphiteUI/ReadAloudController.swift#L670-L682)).
  - Pass the live page text in as a value.
  - Keep only the spell-checker call on the main actor (UIKit requirement, [ReadAloudSpelling.swift:9-11](../../../Sources/GraphiteUI/ReadAloudSpelling.swift#L9-L11)), batched.

#### CC-VOICE-14 Preparation state grows without bound, and a rejected passage is rendered again on every visit
- **Severity:** Low
- **Evidence:**
  - `passageTexts` and `writtenTexts` gain entries for every document and are never cleared ([ReadAloudPassagePreparation.swift:110-113](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L110-L113)).
  - A passage that fails all attempts is discarded from the cache ([ReadAloudPassagePreparation.swift:254](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L254)).
  - `readyTexts` resets on each `prepare` ([ReadAloudPassagePreparation.swift:125](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L125)).
  - Reading the note again therefore renders that passage up to 3 more times ([ReadAloudPassagePreparation.swift:229-230](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L229-L230)).
- **Why it matters:** each attempt costs a full model render. The person waits "Preparing…" again for a passage the system voice will read anyway.
- **Fix direction:** remember rejected keys (in the cache index, keyed like the audio) and clear per-document maps on `cancel`.

#### CC-VOICE-15 Some names are generic or abbreviated against RULES.md
- **Severity:** Low
- **Evidence:**
  - `ReadAloudAudioCacheKey.value` holds a hex digest ([ReadAloudAudioCachePolicy.swift:14](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L14)).
  - `quick` names the system-voice adapter ([NeuralReadAloudSpeech.swift:23](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L23)).
  - `nsError` ([NeuralVoiceDownloader.swift:193](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L193)).
  - The one-letter `$0` closures in the session's sentence navigation ([ReadAloudSpeech.swift:607](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L607), [ReadAloudSpeech.swift:612](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L612)).
  - One concept has three names: "Quick" (mode), "system voice" (UI) and `quick`/`routesToQuick` (code).
- **Why it matters:** RULES.md asks for one name per concept and no vague names such as `value`.
- **Fix direction:** `hexadecimalDigest`, `systemSpeech`, `routesToSystemSpeech`, `downloadError`, and named closure parameters.

## 5. Defects and latent bugs

#### BUG-VOICE-01 Stop in the floating player between two PDF pages does not stop: the next page starts reading
- **Trigger:** The person reads a PDF page range. When a page ends and the next one is being prepared, they tap Stop in the floating player. During preparation the player shows "Preparing…"; Stop stays enabled because the previous page's document is still loaded.
- **Path:**
  1. The last passage ends: `finishCurrentPassage` sets `.finished` and calls `didFinishDocument` ([ReadAloudSpeech.swift:837-838](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L837-L838)).
  2. `continuePDFIfNeeded` runs the continuation ([ReadAloudController.swift:447-451](../../../Sources/GraphiteUI/ReadAloudController.swift#L447-L451)), which calls `loadPDFPage(…, playsWhenReady: true)` ([ReadAloudController.swift:713-714](../../../Sources/GraphiteUI/ReadAloudController.swift#L713-L714)). That starts the page task ([ReadAloudController.swift:643-654](../../../Sources/GraphiteUI/ReadAloudController.swift#L643-L654)) and sets `isPreparing` ([ReadAloudController.swift:636](../../../Sources/GraphiteUI/ReadAloudController.swift#L636)).
  3. Stop is enabled when `session.document != nil` ([ReadAloudFloatingPlayer.swift:222-225](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L222-L225)). It calls `stopAndRewind`, which calls only `reader.session.stop()` and `move(to: 0)` ([ReadAloudNavigator.swift:174-178](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L174-L178)). It does not call `ReadAloudController.stop`, which would cancel `preparation` and change `preparationIdentifier` ([ReadAloudController.swift:414-418](../../../Sources/GraphiteUI/ReadAloudController.swift#L414-L418)).
  4. The page task finishes. Its identifier still matches ([ReadAloudController.swift:660](../../../Sources/GraphiteUI/ReadAloudController.swift#L660), [ReadAloudController.swift:684](../../../Sources/GraphiteUI/ReadAloudController.swift#L684)). `finishPreparing` loads the new page ([ReadAloudController.swift:725](../../../Sources/GraphiteUI/ReadAloudController.swift#L725)), and `session.play()` runs because `playsWhenReady` is true and the state is not `.speaking` ([ReadAloudController.swift:719](../../../Sources/GraphiteUI/ReadAloudController.swift#L719)).
- **Effect:** after pressing Stop, the person hears the next page start a moment later. On a scanned page the wait is several seconds, because preparation runs Vision recognition.
- **Platforms / reach:** iPad, iPhone, Mac; the normal multi-page path with the floating player (on by default, [SettingsView.swift:582](../../../Sources/GraphiteUI/SettingsView.swift#L582)).
- **Confidence:** Traced.

#### BUG-VOICE-02 Stop in the floating player while a fold change is being prepared restarts reading
- **Trigger:** While a note is read aloud, the person folds or unfolds a heading or callout. Before the re-preparation finishes, they tap Stop in the floating player. A large note, or one whose first equation loads the math interpreter, widens the window.
- **Path:**
  1. `MarkdownPane` reports the fold change ([MarkdownPane.swift:127](../../../Sources/GraphiteUI/MarkdownPane.swift#L127)).
  2. `foldsDidChange` captures `wasSpeaking = true` ([ReadAloudController.swift:127](../../../Sources/GraphiteUI/ReadAloudController.swift#L127)) and starts a task that nothing stores ([ReadAloudController.swift:136](../../../Sources/GraphiteUI/ReadAloudController.swift#L136)).
  3. Stop runs `stopAndRewind`, which changes neither `foldPreparationIdentifier` nor `markdownRequest` ([ReadAloudNavigator.swift:174-178](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L174-L178)).
  4. The task's guard passes ([ReadAloudController.swift:141](../../../Sources/GraphiteUI/ReadAloudController.swift#L141)). It then calls `session.load`, `session.move` and, because of the captured flag, `session.play()` ([ReadAloudController.swift:145-147](../../../Sources/GraphiteUI/ReadAloudController.swift#L145-L147)).
- **Effect:** reading resumes on its own after the person stopped it.
- **Platforms / reach:** iPad, iPhone, Mac; Live Preview and Source mode notes with folds, using the floating player.
- **Confidence:** Traced.

#### BUG-VOICE-03 Every sentence skip, passage jump and PDF page break gives up and retakes the audio session, contrary to the documented contract
- **Trigger:** While reading, the person taps Next or Previous Sentence, jumps to a section, or reading reaches the next PDF page.
- **Path:**
  1. Skips go `moveToNextSentence` → `seek` ([ReadAloudSpeech.swift:615-618](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L615-L618)) → `stop()` ([ReadAloudSpeech.swift:656](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L656)).
  2. A page break goes through the continuation to `finishPreparing` → `session.load` ([ReadAloudController.swift:725](../../../Sources/GraphiteUI/ReadAloudController.swift#L725)) → `stop()` ([ReadAloudSpeech.swift:546](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L546)). This bypasses the deliberate "keep audio" answer of `didFinishDocument` ([ReadAloudSpeech.swift:838](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L838)).
  3. `stop()` calls `speech.releaseAudio()` ([ReadAloudSpeech.swift:584](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L584)).
  4. On iOS the Apple adapter calls `setActive(false, options: .notifyOthersOnDeactivation)` ([ReadAloudSpeech.swift:296-304](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L296-L304)). The neural adapter also stops the `AVAudioEngine` and deactivates the session ([NeuralReadAloudSpeech.swift:245-254](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L245-L254)).
  5. `speakCurrentPassage` then activates the session again ([ReadAloudSpeech.swift:252](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L252), [NeuralReadAloudSpeech.swift:162](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L162)).
- **Effect:**
  - Other apps are told they may resume their audio at every skip and every page.
  - Architecture's "the audio session stays active across that page break" is false ([Architecture.md:46](../../../Docs/Architecture.md#L46)).
  - The test named `testAudioIsReleasedWhenReadingStopsOrFinishesButNotBetweenPDFPages` does not check the page case. It reads the release count only after `load` already released ([ReadAloudSessionTests.swift:279-295](../../../Tests/GraphiteAppleTests/ReadAloudSessionTests.swift#L279-L295)).
  - Whether re-activation from the background fails while another app has taken the route is not settled by reading. The deactivate-and-reactivate cycle itself is certain.
- **Platforms / reach:** iPad and iPhone (session deactivation). On the Mac the neural adapter stops and restarts its audio engine at each skip. Normal path.
- **Confidence:** Traced (the release and re-activation); the consequences for other apps are platform behaviour.

#### BUG-VOICE-04 High Quality plays faster speeds at 1.5× while the controls show the chosen speed
- **Trigger:** In High Quality mode the person chooses 1.75× to 3× in the floating player, the popover or Settings.
- **Path:**
  1. The pickers offer 0.75…3 ([ReadAloudVoiceSettings.swift:19](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L19), [ReadAloudFloatingPlayer.swift:250-251](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L250-L251)).
  2. `setSpeed` accepts up to 3 ([ReadAloudSpeech.swift:688-693](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L688-L693)), and the request carries it ([ReadAloudSpeech.swift:738-741](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L738-L741)).
  3. `NeuralReadAloudSpeech` passes it to `player.play(rate:)` ([NeuralReadAloudSpeech.swift:168](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L168)), which clamps it to 1.5 ([RenderedPassagePlayer.swift:39](../../../Sources/GraphiteVoices/RenderedPassagePlayer.swift#L39)).
- **Effect:** the label says 2× or 3×; the audio plays at 1.5×. The leading pause is still divided by the chosen speed ([ReadAloudSpeech.swift:730](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L730)).
- **Platforms / reach:** iPad, iPhone, Mac; High Quality mode, which is the default once a voice is downloaded ([ReadAloudQualityMode.swift:12-15](../../../Sources/GraphiteCore/ReadAloudQualityMode.swift#L12-L15)).
- **Confidence:** Traced.

#### BUG-VOICE-05 Under VoiceOver, Speak Selection or Speak Screen, High Quality reading has no working speed control
- **Trigger:** An assistive speech feature is on, the person follows the system voice (the default), and High Quality mode is active.
- **Path:**
  1. `speedFollowsSystem` is true ([ReadAloudSpeech.swift:507](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L507)) because the neural adapter forwards the system adapter's answer ([NeuralReadAloudSpeech.swift:59](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L59), [ReadAloudSpeech.swift:206-212](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L206-L212)).
  2. The speed control is then hidden in Settings ([ReadAloudVoiceSettings.swift:56](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L56)), replaced by "Speed follows … Speaking Rate" in the popover ([ReadAloudControls.swift:109-112](../../../Sources/GraphiteUI/ReadAloudControls.swift#L109-L112)), and disabled in the floating player ([ReadAloudFloatingPlayer.swift:266](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L266)).
  3. Rendered audio plays at `request.speed`, the stored Graphite speed ([NeuralReadAloudSpeech.swift:168](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L168)). Nothing applies the system's Speaking Rate.
- **Effect:** a person who relies on assistive speech cannot change the reading speed, and the text tells them a system setting controls it when it does not.
- **Platforms / reach:** iPad, iPhone (the property is always false on the Mac, [ReadAloudSpeech.swift:210](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L210)); High Quality mode.
- **Confidence:** Traced.

#### BUG-VOICE-06 A voice download's failure reason is replaced by "Paused" moments after it is shown
- **Trigger:** A voice file fails its checksum, the server answers outside 200–299 (for example a removed revision), or the downloaded file cannot be moved.
- **Path:**
  1. `didFinishDownloadingTo` reports `.failed(…)` and returns ([NeuralVoiceDownloader.swift:162-164](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L162-L164), [NeuralVoiceDownloader.swift:173-176](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L173-L176), [NeuralVoiceDownloader.swift:178-182](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L178-L182)).
  2. URLSession then calls `didCompleteWithError` with no error, since the transfer itself succeeded. That leads to `installIfCompleteWhenIdle` ([NeuralVoiceDownloader.swift:189-191](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L189-L191)) and `installIfComplete` ([NeuralVoiceDownloader.swift:268](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L268)).
  3. The files are incomplete, so `reportPaused` runs ([NeuralVoiceDownloader.swift:280-282](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L280-L282)).
  4. The library stores whichever state arrived last ([NeuralVoiceLibrary.swift:188-189](../../../Sources/GraphiteVoices/NeuralVoiceLibrary.swift#L188-L189)). The row shows "Paused" with Resume instead of the red message ([NeuralVoiceSettings.swift:154-161](../../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L154-L161), [NeuralVoiceSettings.swift:173-176](../../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L173-L176)).
- **Effect:** the person never learns why the download stopped. A permanent server error loops Resume → Paused without explanation.
- **Platforms / reach:** iPad, iPhone, Mac; voice downloads.
- **Confidence:** Traced; the delegate order (finish-downloading, then complete) is URLSession's documented sequence.

#### BUG-VOICE-07 Stopping, closing, choosing Quick or leaving the app mid-render keeps the neural model in memory
- **Trigger:** The person stops or closes reading, switches documents, chooses Quick, deletes the selected voice, or the app resigns active while passages are still rendering. Rendering runs to the end of the document while it is open ([ReadAloudSpeech.swift:737](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L737)).
- **Path:**
  1. Each trigger reaches `ReadAloudPassagePreparation.cancel` or `suspend`:
     - close and Stop: `ReadAloudController.clear` → `session.clear` → `speech.cancelPreparation()` ([ReadAloudController.swift:425](../../../Sources/GraphiteUI/ReadAloudController.swift#L425), [ReadAloudSpeech.swift:594](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L594)) → `preparation.cancel()` ([NeuralReadAloudSpeech.swift:137-139](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L137-L139));
     - Quick or delete: views cancel directly ([NeuralVoiceSettings.swift:16](../../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L16), [NeuralVoiceSettings.swift:91](../../../Sources/GraphiteUI/NeuralVoiceSettings.swift#L91));
     - resign active: `suspend()` ([ReadAloudVoices.swift:24-26](../../../Sources/GraphiteUI/ReadAloudVoices.swift#L24-L26)).
  2. `cancel` and `suspend` cancel the worker task ([ReadAloudPassagePreparation.swift:146](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L146), [ReadAloudPassagePreparation.swift:158](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L158)).
  3. `renderQueue` leaves through `guard !Task.isCancelled else { return }` ([ReadAloudPassagePreparation.swift:213](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L213)), before `renderer.releaseResources()` ([ReadAloudPassagePreparation.swift:220](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L220)).
  4. `NeuralSpeechEngine.loaded` keeps the model until the next completed queue or another voice's load ([NeuralSpeechEngine.swift:111-115](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L111-L115)).
- **Effect:** after reading stops, the app keeps a quarter gigabyte (Pocket TTS) to over three gigabytes (Qwen3-TTS 1.7B) resident; the figures are from the code's own comment ([ReadAloudPassagePreparation.swift:218-219](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L218-L219)). The memory stays while the person writes, and in the background, where iOS ends memory-heavy apps first.
- **Platforms / reach:** iPad, iPhone, Mac on devices (the Simulator cannot load models, [NeuralSpeechEngine.swift:80-81](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L80-L81)); High Quality mode.
- **Confidence:** Traced.

#### BUG-VOICE-08 Unplugging headphones during High Quality reading does not pause it
- **Trigger:** In High Quality mode, while a rendered passage plays, the person disconnects headphones.
- **Path:**
  1. The system-voice adapter treats `oldDeviceUnavailable` as an interruption and pauses ([ReadAloudSpeech.swift:375-390](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L375-L390)). Its events reach the session only while `routesToQuick` is true ([NeuralReadAloudSpeech.swift:41-44](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L41-L44)), and its `activeUtterance` is nil during rendered playback anyway.
  2. `NeuralReadAloudSpeech` observes only `interruptionNotification` ([NeuralReadAloudSpeech.swift:46-50](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L46-L50)), not route changes or `AVAudioEngineConfigurationChange`.
- **Effect:** no pause event reaches the session, so the documented "unplugging the output pauses" ([Architecture.md:17](../../../Docs/Architecture.md#L17)) does not apply to High Quality. Reading either continues out loud through the speaker or stops without the session knowing, depending on how `AVAudioEngine` reacts to the configuration change.
- **Platforms / reach:** iPad and iPhone with wired or Bluetooth outputs; High Quality mode.
- **Confidence:** Partly traced. The missing observation is certain. What `AVAudioEngine` does on its own at a route change cannot be settled by reading.

#### BUG-VOICE-09 Folding or unfolding while reading restarts the current passage from its first word
- **Trigger:** While a passage is read, the person folds or unfolds a section elsewhere in the note.
- **Path:**
  1. `foldsDidChange` records the source location of the word being read ([ReadAloudController.swift:128-129](../../../Sources/GraphiteUI/ReadAloudController.swift#L128-L129)).
  2. It picks the passage containing that location ([ReadAloudController.swift:142-144](../../../Sources/GraphiteUI/ReadAloudController.swift#L142-L144)) and calls `session.move(to: resumeIndex)` ([ReadAloudController.swift:146](../../../Sources/GraphiteUI/ReadAloudController.swift#L146)). That overload resets the offset to 0 through `stop()` ([ReadAloudSpeech.swift:596-603](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L596-L603), [ReadAloudSpeech.swift:590](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L590)).
  3. The edit path does keep the word, through `move(to:offset:)` with `ReadAloudReanchoring.position` ([ReadAloudController.swift:395-397](../../../Sources/GraphiteUI/ReadAloudController.swift#L395-L397)).
- **Effect:** up to a whole passage (at most 1,200 UTF-16 units, [ReadAloudDocument.swift:62](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L62)) is read again. The method's own comment promises it "goes on from where it was" ([ReadAloudController.swift:121-123](../../../Sources/GraphiteUI/ReadAloudController.swift#L121-L123)).
- **Platforms / reach:** iPad, iPhone, Mac; notes with folds.
- **Confidence:** Traced.

#### BUG-VOICE-10 Editing any pronunciation in Settings strips hand-written IPA from the vault's pronunciation file
- **Trigger:** The vault's `.graphite/pronunciations.json` contains an entry in the documented object form, `{"say": …, "ipa": …}` ([ReadAloudPronunciations.swift:52-54](../../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L52-L54)). The person then adds, edits or deletes any term in Settings › Read Aloud › Pronunciations.
- **Path:**
  1. `load` keeps only `(term, say)` ([ReadAloudPronunciationEditor.swift:95-98](../../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L95-L98)).
  2. `save` rebuilds the whole file from those pairs ([ReadAloudPronunciationEditor.swift:101-107](../../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L101-L107)) through `vaultFileData`, which writes `[String: String]` ([ReadAloudPronunciations.swift:80-88](../../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L80-L88)).
  3. The file is replaced atomically ([ReadAloudPronunciationEditor.swift:106](../../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L106)).
- **Effect:** every `ipa` field in a user-authored file inside the vault is deleted without notice. Nothing sounds different today (`usesPhoneticNotation` is off, [ReadAloudPronunciations.swift:41](../../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L41)), but the file loses content the person wrote. OBJECTIVE requires preserving user files.
- **Platforms / reach:** iPad, iPhone, Mac.
- **Confidence:** Traced.

## 6. What to keep

| # | Design | Evidence | Why it is sound |
| ---: | --- | --- | --- |
| 1 | Request-identity filtering of speech events | [ReadAloudSpeech.swift:13-21](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L13-L21), [ReadAloudSpeech.swift:320-333](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L320-L333), [ReadAloudSpeech.swift:773](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L773), [ReadAloudSpeech.swift:786-801](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L786-L801) | A late callback from a cancelled utterance can never advance or highlight a replacement. The `@unchecked Sendable` wrapper states its invariant: it only retains the utterance. |
| 2 | Latest-preparation-wins identifiers with revision checks | [ReadAloudController.swift:115](../../../Sources/GraphiteUI/ReadAloudController.swift#L115), [ReadAloudController.swift:251](../../../Sources/GraphiteUI/ReadAloudController.swift#L251), [ReadAloudController.swift:629-632](../../../Sources/GraphiteUI/ReadAloudController.swift#L629-L632), [ReadAloudController.swift:684-685](../../../Sources/GraphiteUI/ReadAloudController.swift#L684-L685) | Stale pages, selections and documents never install themselves. Ink does not interrupt reading, because only `readingTextVersion` matters. |
| 3 | Refusal instead of guessing in source mapping | [ReadAloudDocument.swift:347](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L347), [ReadAloudDocument.swift:447](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L447), [ReadAloudDocument.swift:656-673](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L656-L673), [ReadingSourceAlignment.swift:55-58](../../../Sources/GraphiteUI/ReadingSourceAlignment.swift#L55-L58) | A highlight is either exact or absent; repeated words are never relocated by text search. |
| 4 | Masking that preserves offsets | [ReadAloudDocument.swift:306-318](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L306-L318), [ReadAloudSection.swift:16-26](../../../Sources/GraphiteCore/ReadAloudSection.swift#L16-L26) | Every masked character keeps its UTF-16 position and line breaks, so parser ranges map straight back to the note. The note itself is never changed. |
| 5 | PDF highlight validation and ownership | [PDFReadAloudSource.swift:135-169](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L135-L169), [PDFReadAloudSource.swift:215-227](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L215-L227), [PDFReadAloudSource.swift:270-299](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L270-L299) | Character counts, composed-character boundaries and the selected text are checked before any highlight. The highlighter removes only its own selections, so the person's selection and search highlights survive. No annotation is written. |
| 6 | Reveal-once following that yields to touch | [PDFReadAloudSource.swift:319-344](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L319-L344), [PDFReadAloudSource.swift:376-383](../../../Sources/GraphiteUI/PDFReadAloudSource.swift#L376-L383) | It never fights a Pencil stroke or a pinch, and it cannot loop on its own geometry updates. |
| 7 | Worker-owned PDFKit objects and a bounded, fall-back-safe extraction | [PDFReadAloudPage.swift:141-180](../../../Sources/GraphiteApple/PDFReadAloudPage.swift#L141-L180), [PDFReadAloudPage.swift:205-235](../../../Sources/GraphiteApple/PDFReadAloudPage.swift#L205-L235) | Only immutable values cross actors. A failed layout match falls back to complete file-order text with a notice; nothing is skipped. |
| 8 | The math interpreter is isolated and bounded | [ReadAloudMarkdownPreparation.swift:7-22](../../../Sources/GraphiteApple/ReadAloudMarkdownPreparation.swift#L7-L22), [ReadAloudMarkdownPreparation.swift:72-91](../../../Sources/GraphiteApple/ReadAloudMarkdownPreparation.swift#L72-L91), [entry.js:60-77](../../../Vendor/math-speech/entry.js#L60-L77), [README.md](../../../Vendor/math-speech/README.md) | An actor owns the JavaScriptCore context. TeX is passed as an argument and never concatenated into code. The cache is bounded by count and size. The bundle is generated from pinned sources with rebuild instructions, so the code embedded in a string has a source of truth. |
| 9 | Pure Core policies with tests | [ReadAloudAudioCachePolicy.swift:8-70](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L8-L70), [ReadAloudQualityMode.swift](../../../Sources/GraphiteCore/ReadAloudQualityMode.swift), [ReadAloudRenderCheck.swift](../../../Sources/GraphiteCore/ReadAloudRenderCheck.swift), [ReadAloudWordAlignment.swift](../../../Sources/GraphiteCore/ReadAloudWordAlignment.swift), [ReadAloudVoiceText.swift](../../../Sources/GraphiteCore/ReadAloudVoiceText.swift), [ReadAloudReanchoring.swift](../../../Sources/GraphiteCore/ReadAloudReanchoring.swift), [ReadAloudPlayerPlacement.swift](../../../Sources/GraphiteUI/ReadAloudPlayerPlacement.swift) | Each is inputs-in, value-out, and has tests (`NeuralReadAloudTests`, `ReadAloudReanchoringTests`, `ReadAloudPlayerAndPenTests`). These are the model for the rest of the area. |
| 10 | A cache key that cannot collide and leaves speed out | [ReadAloudAudioCachePolicy.swift:16-24](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L16-L24) | The NUL separator prevents field-shifting collisions. A version constant invalidates audio on rule changes. Speed changes never discard audio. |
| 11 | Manifest and installation safety | [NeuralVoiceManifest.swift:155-199](../../../Sources/GraphiteCore/NeuralVoiceManifest.swift#L155-L199), [NeuralVoiceInstallation.swift:31-64](../../../Sources/GraphiteVoices/NeuralVoiceInstallation.swift#L31-L64) | Paths cannot escape the voice folder; checksums are well formed. Files are staged and checked against size and SHA-256 before a marker names the revisions. A half-downloaded folder is never taken for a voice. |
| 12 | Background downloads with resume data and bounded retries | [NeuralVoiceDownloader.swift:40-71](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L40-L71), [NeuralVoiceDownloader.swift:187-207](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L187-L207) | Multi-gigabyte downloads survive suspension and lost connections. The `@unchecked Sendable` states its serial-queue invariant. The configuration is injectable for tests. |
| 13 | Real seams for rendering and alignment | [ReadAloudPassagePreparation.swift:8-13](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L8-L13), [ReadAloudSpeechAlignment.swift:8-11](../../../Sources/GraphiteVoices/ReadAloudSpeechAlignment.swift#L8-L11), [ReadAloudPassagePreparation.swift:85-89](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L85-L89) | Each protocol exists for a stated reason (no multi-hundred-megabyte model in tests) and has one production implementation. This is the RULES.md pattern. |
| 14 | MLX failure containment | [NeuralSpeechEngine.swift:44-55](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L44-L55), [NeuralSpeechEngine.swift:131-138](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L131-L138), [NeuralSpeechEngine.swift:215-251](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L215-L251) | MLX errors become thrown errors before samples are read, so a refused graphics command cannot crash the app. The model box documents why `@unchecked Sendable` is safe. |
| 15 | The audio session is released only when it is still Read Aloud's | [ReadAloudSpeech.swift:296-305](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L296-L305), [NeuralReadAloudSpeech.swift:249-253](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L249-L253) | A lecture recording's session is never deactivated by Read Aloud. Keep this rule when merging the two owners (CC-VOICE-07). |
| 16 | Personal Voice is asked for only from an explicit tap; robotic voices are never chosen automatically | [ReadAloudSpeech.swift:65-77](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L65-L77), [ReadAloudSpeech.swift:676-686](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L676-L686), [ReadAloudVoiceSettings.swift:66-73](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L66-L73) | Respects the permission model and the owner's voice decisions. A missing chosen voice is never silently replaced ([ReadAloudSpeech.swift:713-715](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L713-L715)). |
| 17 | Rendered audio stays outside the vault | [ReadAloudAudioCache.swift:35-38](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L35-L38), [NeuralVoiceCatalog.swift:26-35](../../../Sources/GraphiteVoices/NeuralVoiceCatalog.swift#L26-L35) | Audio goes to Caches and voices to Application Support, excluded from backup. Nothing is written into the vault except the user-edited pronunciation file. This is the OBJECTIVE's "no sidecars". |

## 7. Blueprint for this area

### Target shape

| Layer | Type | Single responsibility | Seam |
| --- | --- | --- | --- |
| Core | `ReadAloudDocument` (values + 3 entry points) | The narration document | none |
| Core | `MarkdownNarrationMasking`, `MarkdownNarrationLeaves`, `NarrationAssembler`, `TextRunSourceMapper` | One step of Markdown narration each | none (pure) |
| Core | `PDFPageLines`, `RunningTextFilter`, `HyphenationJoiner`, `SpokenReplacements` | One step of PDF narration each | none (pure) |
| Core | `ReadAloudNotice`, typed `ReadAloudError` | Facts only | Presenter in UI turns them into words |
| Core | `ReadAloudPlaybackState` | The playback state enum and its pure transitions | none |
| Core | `PassageRenderQueue` | Queue, ready set and waiters as a value with pure transitions | none |
| Core | `NeuralVoiceModelFamily` descriptor, `NeuralVoicePlatform`, `ReadAloudVoiceTier` | Model-family and platform policy in one declaration each | none |
| Core | `ReadAloudPreferenceKey` | Every persisted key, raw values pinned | none |
| Apple | `ReadAloudSpeechPlayback` (protocol) | speak, pause, resume, stop, events, release, plus capabilities (speed range, applies system settings, reports word timing) | Real substitution: system voice, neural voice, test fake |
| Apple | `ReadAloudVoiceCatalogue` (protocol) | Installed voices, system voice, Personal Voice | Real substitution: Apple catalogue, test fake |
| Apple | `ReadAloudAudioSessionOwner` | Activate, release, interruption and route events for both adapters | Injected into both adapters |
| Apple | `ReadAloudPlayback` | Drives a `ReadAloudSpeechPlayback` through `ReadAloudPlaybackState` | none |
| Apple | `ReadAloudVoiceSelection`, `ReadAloudSpeechSettings` | Voice choice; speed and highlight mode | Preference store passed in |
| Voices | `AheadOfTimeRendering` (protocol), `NeuralReadAloudSpeech` | High Quality playback over a rendered queue | Neural adapter only; fake in tests |
| Voices | `CheckedPassageRenderer`, `ReadAloudAudioCache` (with injected clock) | Attempts and checks; storage | `NeuralPassageRendering`, `ReadAloudSpeechAligning` (kept) |
| UI | `ReadAloudTransport` | Every user intent: play, pause, `stop(scope:)`, sentence, section, speed | Views call only this |
| UI | `ReadAloudStatus` | Read-only projection for views (status enum for the player) | none |
| UI | `MarkdownReading`, `PDFReading`, `ScannedPageReview`, `FollowReadingPolicy` | One kind of reading each, owning its tasks | none |
| UI | `ListeningQueue`, `RememberedReadingPlaces`, `ReadAloudPenSelection`, `ReadAloudLayoutFrames` | Navigator pieces | `RememberedReadingPlaces` over a key-value store |
| App | Composition root | Builds library, preparation, adapters, controller, navigator; no statics | — |

### Ordered steps (each leaves the app building and behaving the same unless the step fixes a listed bug)

1. **Pin before moving.** Add the tests listed under "Tests that become possible" that need no new seam:
   - cache actor on a temporary folder;
   - `ReadAloudPassagePreparation` with a fake renderer and aligner (both protocols exist);
   - downloader state sequence through the injectable `configuration` with a stubbed `URLProtocol` ([NeuralVoiceDownloader.swift:41](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L41));
   - navigator places on a suite store;
   - a golden test for every persisted key and file name in the invariants below.

   Rename `testAudioIsReleasedWhenReadingStopsOrFinishesButNotBetweenPDFPages` to what it checks, or make it check the page case (expected to fail until step 4).
2. **Key registry.** Introduce `ReadAloudPreferenceKey` with today's raw strings and route all 15 keys and the sample suite through it (CC-VOICE-05). No behaviour change.
3. **One Stop.** Add `ReadAloudTransport` with `stop(scope:)`. It cancels the controller's preparation, the fold and reanchor tasks and the PDF continuation. Point the floating player, popover, close button, Now Playing and navigator at it. Fixes BUG-VOICE-01, BUG-VOICE-02 and LSP-VOICE-03.
4. **Release audio only when reading ends.** Separate "stop speaking" from "give up the route" in the session; `load`, `seek` and `move` no longer release. Introduce `ReadAloudAudioSessionOwner` shared by both adapters, with route-change handling. Fixes BUG-VOICE-03 and BUG-VOICE-08, and CC-VOICE-07.
5. **Split the speech protocol.** Remove the default implementations; add capabilities. The UI reads `supportedSpeedRange` and `appliesSystemSpeechSettings` from the active adapter. Fixes BUG-VOICE-04 and BUG-VOICE-05, and LSP-VOICE-01, -02 and -04.
6. **Playback state enum.** Extract `ReadAloudPlaybackState` and `ReadAloudPlayback`; move the voice catalogue and choice out of the session (SRP-VOICE-03, CC-VOICE-12). The existing 21 session tests stay green.
7. **Split the controller** into `MarkdownReading`, `PDFReading`, `ScannedPageReview` and `FollowReadingPolicy`. The resume location becomes part of the Markdown request, replacing the sleep-poll (SRP-VOICE-01, CC-VOICE-02). Fix the fold path to keep the word offset (BUG-VOICE-09).
8. **Main-actor relief.** Move language recognition and the exported-to-live diff into the page worker (CC-VOICE-13).
9. **Split `ReadAloudDocument`** builders into the Core pieces of section 3.2. The 25 document tests, the reading-view tests and the Live Preview tests stay green (SRP-VOICE-02).
10. **Render queue.** Extract `PassageRenderQueue` and `CheckedPassageRenderer`. Release the model on cancel and on suspension (BUG-VOICE-07), remember rejected keys (CC-VOICE-14), and reconcile the cache index at init (CC-VOICE-11).
11. **Composition root.** Build library, preparation, adapters, controller and navigator in the root. Delete `ReadAloudVoices` statics and `ReadAloudNowPlaying.queueCommands`. Remove I/O default arguments (DIP-VOICE-01, -02, -03).
12. **Typed notices and errors** with one presenter (CC-VOICE-10). **Codable pronunciation entries** (BUG-VOICE-10, ISP-VOICE-03). **Benchmark** moves to its own target (DIP-VOICE-05). **Dead members** are deleted (CC-VOICE-06).

### Behaviour that must be preserved

| ID | Invariant | Test idea |
| --- | --- | --- |
| VOICE-INV-01 | The cache key is the lowercase hexadecimal SHA-256 of `"graphite-read-aloud" ∅ renderSettingsVersion ∅ voiceIdentifier ∅ voiceRevision ∅ text`, where ∅ is U+0000 and `renderSettingsVersion` is 1 ([ReadAloudAudioCachePolicy.swift:11-24](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L11-L24)). Speed is not part of it. | Golden key for a fixed text, voice and revision. |
| VOICE-INV-02 | `voiceRevision` is the voice's source revisions joined with `+` in manifest order ([ReadAloudPassagePreparation.swift:51](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L51)). | Two-source voice yields `r1+r2`. |
| VOICE-INV-03 | The cache folder is `Caches/ReadAloudAudio`. It holds `<key>.m4a`, `<key>.json` and `index.json` ([ReadAloudAudioCache.swift:35-38](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L35-L38), [ReadAloudAudioCache.swift:49-51](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L49-L51)). | Commit one passage on a temporary folder; list file names. |
| VOICE-INV-04 | Details JSON is `{durationSeconds, wordTimings: [{location, length, startSeconds, endSeconds}]?, readsPassageText?}`, with `readsPassageText` omitted when false ([ReadAloudAudioCache.swift:18-22](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L18-L22), [ReadAloudAudioCache.swift:104-106](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L104-L106)). `location` and `length` are UTF-16 offsets into the text the voice read ([ReadAloudWordAlignment.swift:16-32](../../../Sources/GraphiteCore/ReadAloudWordAlignment.swift#L16-L32)). | Golden JSON decode of a fixture written by today's build. |
| VOICE-INV-05 | `index.json` is an array of `{key: {value}, byteCount, lastUsed}`. `lastUsed` uses `JSONEncoder`'s default date encoding (seconds since 2001-01-01) ([ReadAloudAudioCache.swift:141-144](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L141-L144), [ReadAloudAudioCachePolicy.swift:36-47](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L36-L47)). | Decode a fixture index; round-trip. |
| VOICE-INV-06 | Eviction removes least recently used entries first, breaking ties by key. It stops at 250 MiB and never removes protected keys, even over the limit ([ReadAloudAudioCachePolicy.swift:52-70](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L52-L70)). | Existing test; add an actor-level test with an injected clock. |
| VOICE-INV-07 | Rendered audio is AAC, 64 kbit/s, mono, at the model's sample rate ([ReadAloudAudioCache.swift:91-92](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L91-L92)). | Read back the file format with `AVAudioFile`. |
| VOICE-INV-08 | Voices live in `Application Support/Voices/<voice id>`, excluded from backup; staging is `<voice id>.partial`. The marker `.graphite-installed` contains `repository@revision` lines joined by `\n`, and resume data sits at `<localPath>.resume` in staging ([NeuralVoiceCatalog.swift:26-35](../../../Sources/GraphiteVoices/NeuralVoiceCatalog.swift#L26-L35), [NeuralVoiceInstallation.swift:16-29](../../../Sources/GraphiteVoices/NeuralVoiceInstallation.swift#L16-L29), [NeuralVoiceDownloader.swift:238-240](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L238-L240)). | Install from a staged fixture; check names, marker text and `isInstalled`. |
| VOICE-INV-09 | The background session identifier is `com.graphite.study.voice-downloads`. A task description is `<voice id>\n<localPath>` ([NeuralVoiceDownloader.swift:24](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L24), [NeuralVoiceDownloader.swift:227-236](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L227-L236)). Tasks from an earlier launch are found by it. | Parse a description into voice and file; unknown voice → nil. |
| VOICE-INV-10 | The manifest is format version 1 and at most 512 KiB. Paths stay inside the voice folder; checksums are 64 hexadecimal digits, compared in lowercase. The address is `<host>/<repository>/resolve/<revision>/<path>` ([NeuralVoiceManifest.swift:129-199](../../../Sources/GraphiteCore/NeuralVoiceManifest.swift#L129-L199), [NeuralVoiceInstallation.swift:51](../../../Sources/GraphiteVoices/NeuralVoiceInstallation.swift#L51)). | Existing manifest tests; add an uppercase-checksum fixture. |
| VOICE-INV-11 | Persisted preferences keep these keys and value encodings: `GraphiteReadAloudVoiceChoice` (JSON `{identifier, source: picker\|personalVoiceButton}`, at most 4,096 bytes), `GraphiteReadAloudHighlightMode` (`words\|sentences\|off`), `GraphiteReadAloudSpeed` (Double 0.5–3), `readAloudMathematicalStyle` (`concise\|detailed`), `readAloudPDFReadingOrder` (`layout\|file`), `GraphiteReadAloudNeuralVoice` (voice id), `GraphiteReadAloudQualityMode` (`highQuality\|quick`), `GraphiteReadAloudReadsUnpreparedPassagesQuickly` (Bool), `GraphiteReadAloudPlayerCorner` (`ReadAloudPlayerPosition` raw value), `GraphiteReadAloudTapHintShown` (Bool), `GraphiteReadAloudFloatingPlayer` (Bool), suite `com.graphite.study.readAloudSample` (CC-VOICE-05 table). | Registry test pinning every raw value and enum raw value. |
| VOICE-INV-12 | The keys `GraphiteReadAloudVoice` and `GraphiteReadAloudChosenVoice` are deleted at session start and never read ([ReadAloudSpeech.swift:451](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L451), [ReadAloudSpeech.swift:456](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L456)). | Existing `testOldStoredAutomaticPicksAreDroppedAndOnlyRecordedChoicesCount`. |
| VOICE-INV-13 | Remembered places are `GraphiteReadAloudPositions` (`[String: Int]`) and `GraphiteReadAloudPositionsOrder` (`[String]`, least recent first), capped at 300. A note is keyed by `VaultPath.rawValue` with a UTF-16 source location; a PDF by its absolute file path with a page index ([ReadAloudNavigator.swift:53-56](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L53-L56), [ReadAloudNavigator.swift:357-370](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L357-L370), [ReadAloudNavigator.swift:390-395](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L390-L395), [WorkspaceModel.swift:1466](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1466)). | Remember 301 places; the oldest is dropped; keys unchanged. |
| VOICE-INV-14 | The vault pronunciation file is `.graphite/pronunciations.json`, at most 256 KiB and at most 2,000 entries read. Terms are trimmed and at most 64 characters; `say` and `ipa` at most 200. It is written pretty-printed with sorted keys and unescaped slashes, atomically ([ReadAloudPronunciations.swift:48-88](../../../Sources/GraphiteCore/ReadAloudPronunciations.swift#L48-L88), [ReadAloudPronunciationEditor.swift:101-107](../../../Sources/GraphiteUI/ReadAloudPronunciationEditor.swift#L101-L107)). After BUG-VOICE-10 is fixed, `ipa` must round-trip. | Golden write of two entries; decode-encode round trip including `ipa`. |
| VOICE-INV-15 | All speech and source ranges are UTF-16. A passage holds at most 1,200 units; a source at most 1,048,576; total speech at most twice the source budget ([ReadAloudDocument.swift:61-62](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L61-L62), [ReadAloudDocument.swift:450](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L450)). | Existing `testLongPassagesAreBoundedAndDoNotLoseWords`, plus an emoji and CRLF fixture. |
| VOICE-INV-16 | `ReadAloudPassage.id` equals its index in `document.passages` ([ReadAloudDocument.swift:705](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L705)). The transcript and section navigation use `id` as an index ([ReadAloudReader.swift:88](../../../Sources/GraphiteUI/ReadAloudReader.swift#L88), [ReadAloudNavigator.swift:103-105](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L103-L105)). | Property test over Markdown and PDF fixtures: `passages.enumerated().allSatisfy { $0.offset == $0.element.id }`. |
| VOICE-INV-17 | Masking replaces hidden text with U+2060 unit for unit, keeping CR and LF. Math markers are private-use scalars from U+E100 to U+F8FF absent from the note, and one equation is one span with `isEquation` ([ReadAloudDocument.swift:313-317](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L313-L317), [ReadAloudDocument.swift:342-350](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L342-L350)). | A note that contains U+E100 itself still reads its equation. |
| VOICE-INV-18 | A selection that cuts an equation throws `partialEquation`. One that cuts a non-verbatim span throws `partialFormattedText`. Selection endpoints widen to whole words ([ReadAloudDocument.swift:347](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L347), [ReadAloudDocument.swift:447](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L447), [ReadAloudDocument.swift:664-671](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L664-L671)). | Existing tests `testPartialEquationIsRejected` and `testEndpointsExpandCompleteWordsAndRejectBrokenUnicode`. |
| VOICE-INV-19 | Pauses: 0.6 s after a heading, 0.35 s after a paragraph, 0.25 s after a list item, table row or line. Before a heading the pause is at least the heading pause. The pause is divided by speed and capped at 2 s ([ReadAloudDocument.swift:32-38](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L32-L38), [ReadAloudSpeech.swift:833](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L833), [ReadAloudSpeech.swift:730](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L730), [ReadAloudSpeech.swift:268](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L268)). | Existing `testPausesBetweenPassagesFollowWhatTheyAre`; add the cap. |
| VOICE-INV-20 | An event whose request identifier is not the current one changes nothing. A cancelled utterance never advances the document ([ReadAloudSpeech.swift:320-333](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L320-L333), [ReadAloudSpeech.swift:773](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L773)). | Existing `testCompletionAdvancesOnePassageAndStaleCallbacksCannotAdvanceReplacement`; run it in the shared adapter suite. |
| VOICE-INV-21 | Robotic voices (`com.apple.speech.synthesis.voice.*`, `com.apple.eloquence.*`, novelty) are never chosen automatically. A chosen voice that disappears is never replaced silently ([ReadAloudSpeech.swift:41-43](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L41-L43), [ReadAloudSpeech.swift:69](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L69), [ReadAloudSpeech.swift:713-715](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L713-L715)). | Existing session tests on robotic voices and missing voices. |
| VOICE-INV-22 | Personal Voice access is requested only from the button ([ReadAloudVoiceSettings.swift:66-73](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L66-L73)). | Fake catalogue counts requests across a whole reading: 0. |
| VOICE-INV-23 | Read Aloud deactivates the shared audio session only when its own category (`.playback`) is still set ([ReadAloudSpeech.swift:302](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L302), [NeuralReadAloudSpeech.swift:252](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L252)). After step 4 it deactivates only when reading ends. | Fake audio-session owner records activate and release across skips, page breaks and stop. |
| VOICE-INV-24 | Language detection samples at least the first 4,000 UTF-16 units of the passages, needs confidence ≥ 0.6, and otherwise uses the device language ([ReadAloudLanguage.swift:10-23](../../../Sources/GraphiteApple/ReadAloudLanguage.swift#L10-L23)). | English text on a French-locale test → `en-*`. |
| VOICE-INV-25 | Render checks reject audio with:<br>• letter coverage below 0.8;<br>• length over 1.8 × expected and over expected + 4 s;<br>• a loop of four repeats not in the text;<br>• inner silence over 2.5 s at level 0.005.<br>Expected length assumes 14 characters/s plus 0.25 s per comma and 0.4 s per sentence end ([ReadAloudRenderCheck.swift:32-67](../../../Sources/GraphiteCore/ReadAloudRenderCheck.swift#L32-L67), [ReadAloudRenderCheck.swift:142](../../../Sources/GraphiteCore/ReadAloudRenderCheck.swift#L142)). Alignment needs at least half the words matched ([ReadAloudWordAlignment.swift:41](../../../Sources/GraphiteCore/ReadAloudWordAlignment.swift#L41)). | Existing render-check tests, including the real babbling clip. |
| VOICE-INV-26 | Render attempts, in order:<br>1. the chosen voice with its own seed;<br>2. the chosen voice with a random seed;<br>3. Pocket TTS on the passage's own text when installed (cached with `readsPassageText`);<br>4. otherwise the system voice ([ReadAloudPassagePreparation.swift:228-257](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L228-L257)). | Fake renderer that fails twice; assert the third attempt's voice and the flag. |
| VOICE-INV-27 | Codec-model voices get acronyms as written, and voice ranges map back to whole respelled spans ([ReadAloudVoiceText.swift:37-113](../../../Sources/GraphiteCore/ReadAloudVoiceText.swift#L37-L113)). Autoregressive voices render in sentence groups of at most 260 characters ([NeuralSpeechEngine.swift:126](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L126), [NeuralSpeechEngine.swift:148](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L148)). | Existing voice-text tests; add a sentence-group length test. |
| VOICE-INV-28 | Math speech: bundle at `MathSpeech/math-speech.js` exposing `GraphiteMathSpeech.isReady` and `speech(source, detailed)`. At most 8,192 source units; cache of 128 requests or 262,144 combined units. Unsupported expressions are announced as "Equation not yet supported." ([ReadAloudMarkdownPreparation.swift:56-90](../../../Sources/GraphiteApple/ReadAloudMarkdownPreparation.swift#L56-L90), [ReadAloudDocument.swift:361](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L361)). | Existing `ReadAloudMathematicsTests`. |
| VOICE-INV-29 | The callout fold key is `type.lowercased() + "\|" + trimmed title`, shared with `CalloutFoldStore` ([ReadAloudFolding.swift:10-12](../../../Sources/GraphiteCore/ReadAloudFolding.swift#L10-L12)). | Golden key for `> [!NOTE]-  Title `. |
| VOICE-INV-30 | PDF reading continues only while `readingTextVersion` is unchanged, or after reanchoring by page identity. Ink never interrupts. A removed page pauses with a message ([ReadAloudController.swift:301-348](../../../Sources/GraphiteUI/ReadAloudController.swift#L301-L348)). | Existing `testInkOnThePageReadKeepsReadingAndItsHighlight`, `testPDFPageTurnedBetweenLazyPagesReadsOn`. |
| VOICE-INV-31 | Scanned pages always wait for Play after preparation. Corrections stay in memory and are bounded to 256 UTF-16 units on one line ([ReadAloudController.swift:716-719](../../../Sources/GraphiteUI/ReadAloudController.swift#L716-L719), [PDFReadAloudPage.swift:75-78](../../../Sources/GraphiteApple/PDFReadAloudPage.swift#L75-L78)). | Existing `testMixedPDFPausesForScanReviewCorrectionsKeepWordGeometryAndSourceFile`. |
| VOICE-INV-32 | Now Playing answers commands only while a passage is loaded. Next and previous track drive the queue first, then sentences; skip intervals are 10 ([ReadAloudNowPlaying.swift:24-26](../../../Sources/GraphiteUI/ReadAloudNowPlaying.swift#L24-L26), [ReadAloudNowPlaying.swift:62-70](../../../Sources/GraphiteUI/ReadAloudNowPlaying.swift#L62-L70)). | Inject a command-center port; assert registration and removal. |
| VOICE-INV-33 | Running headers and footers: at most 8 remembered per read ([ReadAloudController.swift:688](../../../Sources/GraphiteUI/ReadAloudController.swift#L688)). A first or last line of at most 90 characters, without closing punctuation, carrying the page label is dropped ([ReadAloudDocument.swift:117-131](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L117-L131)). | Existing `testSlideLinesBulletsFootersAndBrokenWordsReadNaturally`. |

### Tests that become possible once the seams exist

- **One contract suite for `ReadAloudSpeechPlayback`.** It runs against the system adapter (hosted, with an installed voice), the neural adapter (fake renderer and aligner, temporary cache, fake audio-session owner) and the test fake. It covers:
  - event order: started, spoken, finished;
  - stale-request rejection;
  - pause and resume;
  - honouring the reported speed range;
  - route-change pause;
  - no `.cancelled` after the adapter's own `stop`.
- **`PassageRenderQueue` transition tests** (pure): deduplication by suffix, moving the waited passage to the front, cancel resuming waiters, suspension keeping waiters.
- **`CheckedPassageRenderer`:** attempt order, fallback flag, model release after cancel and after suspension (BUG-VOICE-07).
- **`ReadAloudAudioCache` with an injected clock:** LRU stamping, index round-trip, reconciliation of unknown files, protected keys.
- **`NeuralVoiceDownloader` with a stubbed `URLProtocol`:** progress, checksum failure keeps the failed state (BUG-VOICE-06), resume data, retry limit.
- **`ReadAloudTransport.stop(scope:)`:** no reading starts after Stop during a page transition or a fold re-preparation (BUG-VOICE-01, -02).
- **`ReadAloudPlayback` state machine:** every intent from every state, no flags.
- **`RememberedReadingPlaces` and `ListeningQueue`** on an in-memory store: ordering, the cap, PDF and note identifiers.
- **Golden tests for every persisted key, file name and JSON shape** (VOICE-INV-01 to -14).

## 8. Appendix: raw metrics

### Reconnaissance numbers (kept, with my checks)

**Functions over 40 code lines (19, reconnaissance).** I checked the spans of the first five and of `preparePDFSnapshot` and `receive` by reading.

| Function | Code lines | Location |
| --- | ---: | --- |
| `ReadAloudDocument.markdown` | 273 | ReadAloudDocument.swift:296 |
| `ReadAloudDocument.pageText` | 149 | ReadAloudDocument.swift:79 |
| `ReadAloudScanReview.body` | 75 | ReadAloudReader.swift:177 |
| `NeuralVoiceBenchmark.run` | 68 | NeuralVoiceBenchmark.swift:144 |
| `ReadAloudReader.options` | 64 | ReadAloudReader.swift:46 |
| `ReadAloudVoiceSettings.voiceSection` | 62 | ReadAloudVoiceSettings.swift:38 |
| `ReadAloudFloatingPlayer.pageMenu` | 60 | ReadAloudFloatingPlayer.swift:270 |
| `ReadAloudController.preparePDFSnapshot` | 59 | ReadAloudController.swift:657 |
| `PDFReadAloudExtraction.recognizedPage` | 58 | PDFReadAloudPage.swift:276 |
| `PDFReadAloudExtraction.layoutPage` | 55 | PDFReadAloudPage.swift:183 |
| `ReadAloudAudioTiming.init` | 50 | ReadAloudAudioTiming.swift:22 |
| `Parser.atom` | 50 | MathSpeech.swift:74 |
| `PDFReadAloudSource.page` | 49 | PDFReadAloudSource.swift:83 |
| `ReadAloudSession.receive` | 49 | ReadAloudSpeech.swift:753 |
| `ReadAloudPronunciationEditor.sections` | 45 | ReadAloudPronunciationEditor.swift:49 |
| `ReadAloudSession.speakCurrentPassage` | 42 | ReadAloudSpeech.swift:710 |
| `ReadAloudSectionPicker.body` | 41 | ReadAloudReader.swift:262 |
| `NeuralVoicesSection.body` | 41 | NeuralVoiceSettings.swift:57 |
| `ReadAloudSection.sections` | 41 | ReadAloudSection.swift:12 |

**Other reconnaissance numbers.**
- Types over 300 code lines: `ReadAloudController` 617, `ReadAloudDocument` 579, `ReadAloudSession` 357, `ReadAloudFloatingPlayer` 303.
- Files over 400 code lines: `ReadAloudSpeech.swift` 698, `ReadAloudController.swift` 660, `ReadAloudDocument.swift` 631.

**Pattern counts (reconnaissance, comment- and string-stripped).**

| Pattern | Reconnaissance count | My check |
| --- | ---: | --- |
| `try?` | 74 | not recounted |
| `Task.sleep` / `sleep` | 9 | 9 (grep `Task\.sleep` over the area: ReadAloudSpeech.swift:818, ReadAloudController.swift:362 and :542, ReadAloudNavigator.swift:159, ReadAloudFloatingPlayer.swift:60 and :354, ReadAloudControls.swift:203, NeuralReadAloudSpeech.swift:165, ReadAloudPassagePreparation.swift:270) |
| `.shared` | 6 | not recounted |
| `static var` | 10 | not recounted |
| `@unchecked Sendable` | 4 | 4, each with a stated invariant: [ReadAloudSpeech.swift:13](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L13), [NeuralSpeechEngine.swift:47](../../../Sources/GraphiteVoices/NeuralSpeechEngine.swift#L47), [NeuralVoiceDownloader.swift:20](../../../Sources/GraphiteVoices/NeuralVoiceDownloader.swift#L20), [ProcessResources.swift:42](../../../Sources/GraphiteVoices/ProcessResources.swift#L42) |
| `MainActor.assumeIsolated` | 7 | not recounted |
| `Date()` / `Date.now` | 12 | not recounted |
| `UserDefaults` | 13 | not recounted |
| `FileManager.default` | 38 | 11 in ReadAloudAudioCache.swift (grep) |
| `URLSession` | 6 | not recounted |
| `NotificationCenter.default` | 7 | not recounted |
| `default:` in switch | 6 | not recounted |
| `[String: Any]` | 4 | not recounted |
| `Task { }` | 37 | not recounted |
| `DispatchQueue.main` | 1 | not recounted |
| `fatalError` | 1 | 1, an unavailable `init(coder:)` ([ReadAloudPen.swift:189](../../../Sources/GraphiteUI/ReadAloudPen.swift#L189)) |

**Commits touching each file (reconnaissance):** `ReadAloudController.swift` 15, `ReadAloudSpeech.swift` 14, `ReadAloudDocument.swift` 9, `ReadAloudVoiceSettings.swift` 8, `ReadAloudReader.swift` 7, `PDFReadAloudSource.swift` 7, `ReadAloudControls.swift` 5, `ReadingSourceAlignment.swift` 4, `ReadAloudNavigator.swift` 4, `NeuralVoiceLibrary.swift` 3, `ReadAloudFloatingPlayer.swift` 3, `NeuralVoiceSettings.swift` 3, `ReadAloudMarkdownPreparation.swift` 3, `RenderedPassagePlayer.swift` 2, `ReadAloudSpeechAlignment.swift` 2.

### Counts I made

**Stored properties, counted by reading.**

| Type | Stored properties | Location |
| --- | ---: | --- |
| `ReadAloudController` | 39 | [ReadAloudController.swift:29-82](../../../Sources/GraphiteUI/ReadAloudController.swift#L29-L82), plus line 553 |
| `ReadAloudSession` | 24 | [ReadAloudSpeech.swift:398-441](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L398-L441) |
| `ReadAloudNavigator` | 19 | [ReadAloudNavigator.swift:19-52](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L19-L52), lines 170 and 239-242 |
| `ReadAloudPassagePreparation` | 18 | [ReadAloudPassagePreparation.swift:59-83](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L59-L83), line 260 |
| `NeuralReadAloudSpeech` | 14 | [NeuralReadAloudSpeech.swift:17-35](../../../Sources/GraphiteVoices/NeuralReadAloudSpeech.swift#L17-L35) |

**Reset lists in `ReadAloudController`, counted by reading.** `begin` sets 26 fields; `clear` sets 17 fields after `stop` and `session.clear`; `documentDidChange` sets 6.

**`ReadAloudSpeaking` requirements:** 16, of which 10 have default implementations ([ReadAloudSpeech.swift:101-153](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L101-L153)).

**View reach-through.** 67 lines of `reader.session.` in `Sources/GraphiteUI/*.swift` (grep `reader\.session\.`).

**Persisted keys.** 15 keys and 1 suite name in 8 files (grep `Key = "|forKey: "|AppStorage\("|suiteName: "`, plus `SettingsView.swift:582`).

**Static service-locator references.** 11 (grep `ReadAloudVoices\.(preparation|library)`).

**`message` assignments in `ReadAloudSession`.** 11, counted by reading: lines 551, 563, 594, 672, 682, 684, 714, 717, 744, 749, 768.

**Tests in the area (grep `func test` per file): 136.**

| Test file | Tests |
| --- | ---: |
| ReadAloudDocumentTests | 25 |
| ReadAloudControllerTests | 24 |
| NeuralReadAloudTests (manifest, cache policy, alignment, quality mode, render check, voice text) | 21 |
| ReadAloudSessionTests | 21 |
| ReadAloudPronunciationTests | 7 |
| ReadAloudReadingViewTests | 7 |
| PDFReadAloudExtractionTests | 7 |
| ReadAloudMathematicsTests | 6 |
| ReadAloudAudioTimingTests | 4 |
| PDFReadAloudScanTests | 4 |
| ReadAloudReanchoringTests | 3 |
| ReadAloudFoldingTests | 3 |
| ReadAloudPlayerAndPenTests | 3 |
| ReadAloudNativeSpeechTests | 1 |

The hosted suites `App/Tests/ReadAloudLectureHighlightTests.swift` (815 lines), `ReadAloudScanHighlightTests.swift` (160) and `ReadAloudWhileWritingTests.swift` (297) also drive the production controller. Zero tests name `NeuralReadAloudSpeech`, `ReadAloudPassagePreparation`, `RenderedPassagePlayer`, `NeuralVoiceLibrary`, `NeuralVoiceDownloader`, `NeuralSpeechEngine`, `OnDeviceSpeechAlignment`, the `ReadAloudAudioCache` actor or `ReadAloudNavigator` (grep over `Tests/**` and `App/Tests/**`).

### Findings and bugs tally

| Severity | Findings |
| --- | --- |
| High (4) | SRP-VOICE-01, SRP-VOICE-02, LSP-VOICE-01, OCP none |
| Medium (22) | SRP-VOICE-03, -04, -05; OCP-VOICE-01; LSP-VOICE-02, -03; ISP-VOICE-01, -02, -03; DIP-VOICE-01, -02; CC-VOICE-01, -02, -03, -04, -05, -07, -10, -11, -12, -13 |
| Low (12) | OCP-VOICE-02; LSP-VOICE-04, -05, -06; DIP-VOICE-03, -04, -05; CC-VOICE-06, -08, -09, -14, -15 |

The High row has three entries: SRP-VOICE-01, SRP-VOICE-02 and LSP-VOICE-01 ("OCP none" means no OCP finding is High). Totals: 3 High, 21 Medium, 12 Low, 36 findings in all.

Bugs: 10 (BUG-VOICE-01 to -10); 9 traced, 1 partly traced (BUG-VOICE-08). Invariants: 33 (VOICE-INV-01 to -33).

### Correction to an earlier section

ISP-VOICE-02 cites the Transcript rows as starting playback without the `isPreparing` guard. The rows have no guard of their own ([ReadAloudReader.swift:87-90](../../../Sources/GraphiteUI/ReadAloudReader.swift#L87-L90)), but the sheet shows a progress view instead of the rows while preparing ([ReadAloudReader.swift:19-20](../../../Sources/GraphiteUI/ReadAloudReader.swift#L19-L20)). The unguarded case that is reachable is the floating player's sentence buttons. They stay enabled while `isPreparing` ([ReadAloudFloatingPlayer.swift:213-232](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L213-L232)), whereas its Play button is disabled ([ReadAloudFloatingPlayer.swift:243](../../../Sources/GraphiteUI/ReadAloudFloatingPlayer.swift#L243)) and the popover disables the whole transport ([ReadAloudControls.swift:161](../../../Sources/GraphiteUI/ReadAloudControls.swift#L161)).

### What I could not read completely

`Sources/GraphiteApple/Resources/MathSpeech/math-speech.js` is a generated, minified bundle: 58 physical lines, each tens of thousands of characters long. `read_files` truncated it after line 43. I read its source of truth, [Vendor/math-speech/entry.js](../../../Vendor/math-speech/entry.js) (77 lines), and [Vendor/math-speech/README.md](../../../Vendor/math-speech/README.md) completely. I located the exported `GraphiteMathSpeech` object with grep. Every other file in scope was read in full.

### Tally correction

The row labels "High (4)" and "Medium (22)" in the tally table above are miscounted. The authoritative counts are:

| Severity | Count | Findings |
| --- | ---: | --- |
| High | 3 | SRP-VOICE-01, SRP-VOICE-02, LSP-VOICE-01 |
| Medium | 21 | SRP-VOICE-03, -04, -05; OCP-VOICE-01; LSP-VOICE-02, -03; ISP-VOICE-01, -02, -03; DIP-VOICE-01, -02; CC-VOICE-01, -02, -03, -04, -05, -07, -10, -11, -12, -13 |
| Low | 12 | OCP-VOICE-02; LSP-VOICE-04, -05, -06; DIP-VOICE-03, -04, -05; CC-VOICE-06, -08, -09, -14, -15 |
