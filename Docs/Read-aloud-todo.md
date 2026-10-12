# Read aloud with a natural human voice: implementation TODO

Created: 2026-10-10.

Status: implementation in progress, 2026-10-11. Checked items below identify implemented portions; unchecked items remain open, including partially implemented tasks whose complete acceptance criteria are not met. See `Coverage.md` for actual test/build evidence and outstanding device validation. The owner has deferred voice improvements so functional work can proceed. Human-sounding voice acceptance remains future work, rather than a blocker for this increment. This document retains the owner's complete request and does not redefine the product scope in `OBJECTIVE.md`.

Current increment: temporary local Apple voices, remembered voice/speed, fixed-sample and current-passage voice previews, Markdown document/selection/cursor/start-end/heading-section reading, PDF document/page/page-range/native-selection/start-end reading with exact cross-page anchors, previous/next sentence and repeat-passage controls, a reviewable transcript with callback-driven word highlighting, temporary Markdown Source/Live Preview/Reading-view and original PDF-page highlights, explicit Show in PDF navigation, optional source following, and offline structured English math speech. PDF Page Layout order uses on-device paragraph detection on macOS/iOS 26+, maps every original token to native page coordinates, and falls back visibly to file order for uncertain layouts/tables or older systems. File Order remains selectable and remembered. Image-only pages now use bounded on-device text recognition, pause for review, and highlight recognized word rectangles; temporary word corrections retain those rectangles. Scanned transcript words can define inclusive start/end points on the current page, preserving corrections and stopping before the next page. Read Section Pages uses available PDF outlines, explicitly including full boundary pages; exact outline heading endpoints remain open. Mixed native/scanned documents are read one page at a time. MathJax plus Speech Rule Engine now handle base/AMS equations, including sums, products, integrals, limits, derivative notation, vectors, matrices, cases and aligned rows, with remembered concise/detailed modes. Unknown commands and exceeded limits are announced; custom macros, arbitrary TeX documents and PDF math recognition remain open. Rendered Markdown mapping requires complete token agreement; unsupported transformations retain transcript highlighting. Formulas highlight as whole expressions. No cloud provider or owner listening approval is claimed.

Voice decision, 2026-10-11: the owner rejected the Apple Enhanced audition ("sounded horrific"). This supersedes the earlier tentative acceptance. The roughly 30-second Enhanced sample used `com.apple.siri.natural.Nora`, displayed as Voice 4, en-US, at the production adapter's default rate and pitch. The Standard comparison used Samantha. Neither is an approved default-quality voice. Keep the native provider available for explicit audition/fallback use while evaluating a different engine. Do not try to satisfy the requirement by renaming Apple's quality tier or changing a pitch slider.

Voice priority update, 2026-10-11: the owner said "we can make the voice nicer later". Keep the current local engine for functional development; do not treat the rejected audition as approved or delay document reading for another voice decision. When voice work resumes, establish online/offline preferences, audition another engine with the same technical passage, then integrate the accepted voice and measure real audio/highlight synchronization. ElevenLabs' [speech-with-timing endpoint](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps) documents original and normalized character timings; original-text agreement must be validated before drawing source highlights. Its documentation states zero-retention requests require enterprise access, so ordinary account requests must not be described as zero retention. An offline candidate is [Kokoro Swift](https://github.com/mweinbach/kokoro-swift); dependency/model licensing, device resource use, source alignment, and listening quality still need evaluation. Neither candidate is integrated or approved. Do not transmit a document, create a paid account, or purchase credits to audition without the corresponding authorization.

## Product outcome

Let the user listen to a Markdown note or PDF paper in a normal, human-sounding voice while following a highlight on the words being spoken. Support the whole document, a selection, a section, a page range, or a passage with chosen start and end points. Interpret Markdown formatting and LaTeX mathematics before narration. Preserve the user's files.

**Natural voice quality is a core requirement. A robotic voice does not satisfy the requested feature, even if playback and highlighting work.**

## 1. Define supported documents and completion evidence

- [ ] Support Markdown notes containing prose, Obsidian syntax, inline LaTeX, and display equations.
- [ ] Support PDFs containing selectable text, including scientific papers and lecture slides.
- [ ] Track scanned pages, mixed scanned/text PDFs, and mathematical recognition as a separate implementation increment with its own accuracy evidence.
- [ ] Treat standalone `.tex` documents as a separate extension requiring TeX parsing, macro handling, and include-file policy. Embedded LaTeX support does not establish full LaTeX document support.
- [ ] Document supported languages, mathematical constructs, document layouts, operating systems, and device requirements.
- [ ] Collect representative owner-approved notes and papers for evaluation. Use public or synthetic fixtures in repository tests.
- [x] Keep implementation status, automated verification, listening review, and physical-device validation separate in `Coverage.md`.

## 2. Make the voice sound human

### Voice selection and listening review

- [ ] Audition native Apple voices, cloud speech services, and suitable on-device speech models against the same passages. Select providers after listening and device measurement.
- [ ] Evaluate calm, clear narration suited to sustained study. Check sentence intonation, punctuation, paragraph pauses, heading pauses, and emphasis.
- [ ] Reject metallic sound, clipped endings, monotone delivery, unexplained pauses, repeated syllables, and audible joins between generated passages.
- [ ] Check continuity across chunks: maintain the selected voice, accent, loudness, pronunciation, and speaking style throughout a paper.
- [ ] Check long passages as well as short demos. Listen to at least ten minutes of continuous technical narration before approving a voice.
- [ ] Evaluate the default speed and several faster/slower settings. Speed controls must preserve intelligibility and avoid unintended pitch changes.
- [ ] Include proper names, acronyms, Greek letters, units, dates, decimals, negative numbers, abbreviations, citations, and mixed prose/math in the audition.
- [x] Offer a preview using a fixed sample and an optional passage from the current document, with the same engine and processing path used in playback.
- [ ] Show the voice's language, accent where available, download requirement, offline availability, and any usage cost before selection.
- [x] Let the user choose and remember a preferred voice. Do not substitute another provider, voice, or language without explaining the change.
- [ ] Support document-appropriate language selection and an explicit override. Evaluate mixed-language passages before promising automatic switching.
- [ ] Add a pronunciation dictionary for technical terms and names. Keep overrides separate from source content and invalidate affected cached speech when they change.

### Acceptance gate for natural narration

These are proposed release criteria, not measured results.

- [ ] Agree with the owner on the audition passages and acceptable voice before committing to a provider.
- [ ] Record the exact provider, model/version where available, voice, language, speed, device, and review date for each audition.
- [ ] Have the owner rate naturalness, listening comfort, technical pronunciation, and continuity from 1 to 5. Target at least 4 in each category for the preferred voice.
- [ ] Correct omissions, repetitions, altered numbers, and altered mathematical statements found in the acceptance passages. A pleasant voice cannot compensate for changed content.
- [ ] Verify that the production playback path matches the approved audition, including chunk boundaries and speed changes.
- [ ] If only a fallback voice is available, describe it as a fallback and keep the preferred-quality requirement open.

### Speech provider capabilities

- [ ] Inspect `AVSpeechSynthesizer` and available device voices for native playback, pause/resume, rate control, and spoken-range callbacks. Verify supported voices on physical devices.
- [ ] Evaluate cloud services that return audio plus word or character alignment, such as ElevenLabs. Verify timing support for the specific chosen model and endpoint.
- [ ] If a preferred voice lacks usable timing, evaluate forced alignment against the generated audio. Measure its accuracy and added delay before adopting it.
- [ ] For an on-device model, measure download size, license terms, memory, battery use, startup latency, sustained playback, and timing support on supported iPads.
- [ ] Use a focused provider boundary for speech generation, timing, cancellation, available voices, and capability reporting. Keep provider details out of document views.
- [ ] Handle provider normalization of numbers and abbreviations through an explicit mapping to the original passage.
- [ ] Keep cloud credentials in secure device storage or a secure service boundary. Ship no private service keys in the application.
- [ ] Document pricing units, expected cost for representative papers, request limits, retention terms, and network requirements before choosing a service. Recheck these during implementation.
- [ ] Obtain the user's choice to enable cloud narration before transmitting document passages. Send the requested passage and only the bounded context needed for continuity.
- [ ] Provide offline behavior with a clear choice to wait, use downloaded audio, or switch to an available local voice. Preserve the reading position.
- [ ] Cancel unused generation and bound prefetching so stopping or seeking does not generate an entire paper at the user's expense.

## 3. Read exactly the requested passage

- [ ] Add **Read Document**, **Read From Here**, and **Read Selection** to relevant document controls and selection menus.
- [ ] Add **Set Reading Start**, **Set Reading End**, and **Read Range** for passages that are inconvenient to select in one gesture.
- [x] Support a range across PDF pages and across Markdown blocks, including an endpoint within a paragraph. PDF endpoints currently come from native text selection; separate start/end markers remain open above.
- [x] Show the chosen range before starting. Reject reversed or empty ranges with a useful explanation.
- [ ] Define endpoints as the complete chosen start word through the complete chosen end word, inclusive. Represent mathematical endpoints with valid expression/term boundaries.
- [ ] Add section reading from Markdown headings and available PDF outlines. Provide manual ranges when the PDF has no usable outline.
  - Markdown heading ranges are implemented. PDF Read Section Pages follows nested outlines and includes full boundary pages with explicit disclosure; exact semantic heading endpoints remain open. Scanned review lists offer indexed Start Here/End Here for one page, including corrected phrases; direct page-tap and cross-page recognized endpoints remain open.
- [x] Add PDF page-range reading and distinguish printed page labels from physical page positions when they differ. The picker explicitly uses physical page positions.
- [ ] Let the user begin at a tapped word or paragraph through an explicit reading action that does not interfere with selection, links, or Pencil writing.
- [ ] Stop at the requested endpoint without reading the next sentence, page, or section. Generation context outside the range must not become audible output.
- [ ] Narrate the selected content faithfully. Summaries, explanations, and paraphrases are separate features outside this reader's default behavior.
- [ ] Preserve the active range after pause/resume, seek, a voice change, and interruptions where the document revision still matches.
- [ ] Offer keyboard and accessibility equivalents for choosing endpoints and starting playback.
- [ ] Treat spoken commands such as “read from here” as an optional later input method. The initial controls must work through touch, selection, and keyboard without a microphone.

## 4. Interpret Markdown and Obsidian syntax

- [x] Use the existing Markdown parser and semantic structures. Avoid stripping punctuation with a single regular expression.
- [ ] Read heading text with a heading pause. `## Introduction` must sound like “Introduction.”
- [x] Speak emphasis content while omitting `**`, `_`, `~~`, and highlight/color markers. Preserve punctuation that carries meaning.
- [ ] Read link labels and Wikilink aliases. Offer an explicit action for spelling a destination or URL.
- [ ] Read lists in order, with pauses and a preference for announcing list numbers or task state.
- [ ] Read callout titles and bodies, including nested callouts, with coherent pauses.
- [ ] Skip YAML properties, comments, block identifiers, and formatting syntax by default. Offer relevant metadata as an explicit reading choice.
- [ ] Offer footnotes inline, at the end, or skipped. Keep footnote navigation separate from the main passage position.
- [ ] Offer citation/reference reading preferences without deleting substantive sentences around references.
- [ ] Define table narration by row with column headers. Support reading a selected cell or row and skipping a table.
- [ ] Offer code-block choices: skip with an indication, read as text, or spell symbols. Inline code needs its own preference.
- [ ] Read meaningful image descriptions/captions when present. Do not invent a description of an image or diagram.
- [ ] Make embedded-note reading explicit, bounded, and cycle-safe. Do not follow arbitrary links or fetch remote attachments during narration.
- [ ] Give dynamic Bases and other rendered content a stable reading snapshot or explain that the content is unsupported.
- [x] Support starting narration from Reading view, Live Preview, and Source mode while applying the same semantic reading rules.
- [x] Preserve source bytes, frontmatter, line endings, links, and formatting. Preparing narration must not save or rewrite the note.

### Required examples

| Source | Expected narration |
| --- | --- |
| `## Introduction` | “Introduction,” followed by a heading pause |
| `**Important result**` | “Important result” |
| `[the paper](https://example.com)` | “the paper” |
| `[[Fourier Transform|the transform]]` | “the transform” |
| `$x^2$` | “x squared” |
| `The result is $\frac{x^2}{2}$.` | “The result is x squared over two.” |
| `~={#ff0000}Warning=~` | “Warning” |

## 5. Read mathematics with structure

- [x] Parse mathematical expressions into a structure that preserves grouping and operators before producing speech. Production preparation uses MathJax MathML and Speech Rule Engine; unsupported syntax is announced.
- [x] Evaluate and integrate MathJax and Speech Rule Engine for speech generation. Pinned offline JavaScriptCore bundle, licenses, source inventory and rebuild instructions are in `Vendor/math-speech`; native rendering remains separate.
- [x] Start from the original equation source for semantics. Rendering compatibility rewrites must not change the mathematical statement being spoken.
- [x] Support inline/display equations, fractions, powers, roots, subscripts, Greek letters, relations, grouped expressions, and named operators through bounded base/AMS interpretation.
- [x] Extend coverage to sums, products, limits, integrals and bounds, derivative notation, vectors, matrices, piecewise expressions, and aligned equation rows. Descriptions preserve notation; contextual mathematical interpretation is not inferred.
- [x] Offer concise ClearSpeak and detailed MathSpeak speech. Detailed mode retains structural boundaries; changing mode prepares the chosen range again and waits for Play.
- [x] Verify distinctions such as `(a+b)/c` versus `a+b/c` and `-x^2` versus `(-x)^2`; script behavior is also covered by the existing source-mapping tests.
- [ ] Define pronunciation choices for symbols with multiple uses, such as an index `i` and the imaginary unit. Support explicit overrides rather than claiming universal contextual understanding.
- [ ] Support equation labels and references without reading TeX commands aloud. Let the user choose whether to announce equation numbers.
- [ ] Handle supported macros through bounded expansion. Report unknown commands or unsupported structures and offer skipping, literal source, or stopping at that expression.
- [x] Keep mathematical speech faithful to notation. Do not ask a general-purpose generative model to improvise an equation's meaning in the standard narration path.
- [ ] Treat recognition of a PDF equation as separate from interpreting known LaTeX. A visually correct PDF need not retain its source expression.
- [ ] Highlight a whole equation when term mapping is unavailable, with a clear capability limit. Track accurate term-by-term highlighting as separate work.
  - Implemented for source-mapped Markdown equation attachments and numbered display equations. Unsupported rendering transformations disable that block's mapping; individual terms and recognized PDF equations remain open.
- [ ] For term highlighting, connect spoken phrases to expression nodes and their actual rendered bounds. Several spoken words can correspond to one symbol or group.
- [ ] Provide repeat-equation and read-equation-in-detail actions without losing the surrounding prose position.
- [ ] Review mathematical pronunciation and structural accuracy with the owner using real course material.

## 6. Extract PDF papers in reading order

- [x] Use PDFKit text extraction, selections, and character bounds for text PDFs. Keep framework object ownership consistent with documented threading constraints.
- [ ] Build a page-local reading model with stable passage identifiers and page coordinates. Extract only the requested pages and bounded lookahead.
  - Implemented immutable original/prepared text and exact per-token page ranges, one requested page at a time. Native endpoints map through these ranges; durable passage/checkpoint identity remains open.
- [ ] Validate single-column, two-column, and mixed-layout papers. Reading order must not jump between columns halfway through a sentence.
  - Synthetic single/two-column and spanning-heading fixtures pass using Apple's on-device paragraph detector. Every original token is retained once. Page Layout/File Order choice rebuilds the range and waits for Play. Tables, uncertain mappings and older systems use complete file-order text with a notice. Real course papers and broader layouts remain to validate.
- [ ] Handle line-break hyphenation, ligatures, Unicode, superscripts, subscripts, and text boxes while preserving mappings back to the page.
- [ ] Detect repeated headers, footers, and page numbers with conservative rules. Provide a preference and a way to inspect or override skipped regions.
- [ ] Distinguish body text, headings, captions, footnotes, tables, references, and equations where extraction permits. Expose uncertainty rather than silently dropping text.
- [ ] Provide preferences for citations, reference lists, captions, tables, and footnotes. Preserve material inside an explicit selection unless the user chooses filtering.
- [ ] Support text/image pages within the same PDF, rotated pages, crop boxes, zoom, and continuous page layouts.
  - Mixed native/scanned page progression, recognized bounds across four rotations/crop boxes, and native iPad highlight placement through zoom now have synthetic integration coverage. Partly embedded-text/partly image pages, physical gesture/Pencil delivery and broader scans remain open.
- [x] Respect document access and extraction permissions. Explain locked documents or unavailable text through the existing password/access flow.
- [x] Detect image-only pages and offer text recognition. Read starts local recognition for a page without embedded text, then waits for transcript review and Play. Blank/unrecognized pages report failure.
- [ ] Add optical character recognition with word bounds for scans. Evaluate mathematical recognition through its own fixtures and confidence handling.
  - Text recognition and temporary word-region highlights are implemented with Apple's document/text recognizers. Mathematical recognition is still separate and incomplete; text recognition must not be described as accurate equation understanding.
- [x] Make uncertain recognized text inspectable and correctable in the derived reading transcript. Keep the source PDF unchanged. Review Recognized Words accepts bounded one-line corrections, retains the original region, rebuilds offsets/playback, and rejects stale review requests. Recognition flags derive from line confidence and cannot guarantee correctness.
- [ ] For uncertain reading order or equation recognition, let the user select a region, review the transcript, skip it, or stop. Do not promise exact narration of arbitrary scientific PDFs.

## 7. Synchronize speech and highlights

- [ ] Maintain explicit mappings between source locations, rendered locations, prepared spoken text, and audio timing/spoken-range events.
- [ ] Handle one-to-many and many-to-one mappings, including symbols, pronunciation overrides, removed markup, joined PDF words, and normalized numbers.
- [ ] Define Unicode coordinate conversions across Swift strings, UTF-16 framework ranges, provider character offsets, and PDF character indexes. Test combining marks and emoji.
- [x] Drive highlights from actual playback position or native speech callbacks. Do not estimate word timing by dividing sentence duration.
- [ ] Group provider character timings into spoken words and map them to document ranges. Validate missing, malformed, overlapping, or out-of-order timing information.
- [x] Reset timing offsets at chunk boundaries while retaining the document's reading position. Reject callbacks belonging to canceled playback sessions.
- [ ] Highlight the current word and optionally shade its sentence for context. Use theme-aware colors and an accessible non-color position indicator.
- [x] Draw highlights as temporary presentation state. Do not insert Markdown markers or write PDF annotations.
- [x] Highlight original PDF text using exact native selection/page anchors, with round-trip coordinate validation. Preserve native text selection and existing search highlights; source offsets never come from searching for repeated words.
- [x] Implement rendered-word location reporting for Textual and TextKit. Source tokens are validated against the entire rendered block in order before attaching exact original ranges; repeated spellings are not searched.
- [ ] Account for native formula attachments: their whole-expression frame is not sufficient evidence for individual term bounds.
- [ ] Recalculate visible geometry after scrolling, zoom, rotation, text-size changes, folding, and window resizing without changing the semantic reading anchor.
- [ ] Automatically reveal the active passage with comfortable margins. Manual scrolling should suspend following until the user chooses **Follow Reading**.
- [ ] Preserve normal text selection and Pencil interactions. Reading highlights must not steal the selection or add undo steps.
- [ ] Measure alignment on device recordings of playback and highlights. Agree on acceptable tolerance before release and record observed drift across long passages.

## 8. Playback controls and session behavior

- [x] Provide play, pause, resume, stop, previous/next sentence, repeat passage, speed, voice, and **Follow Reading** controls. Device gesture delivery and sustained playback still require validation.
- [ ] Show the document, active range, current section/page, and buffering or error state without crowding the study interface.
- [x] Keep playback session ownership separate from a document view so tab navigation does not recreate the speech engine.
- [ ] Define switching documents and vaults: stop before releasing required file access, preserve a valid checkpoint, and show which document is speaking.
- [ ] Store a device-local resume checkpoint using document identity, revision, and semantic anchor. Revalidate it after external edits, renames, page changes, or note edits.
- [x] On an edit affecting the passage, pause and rebuild or ask the user to restart from a known anchor. Never continue highlighting unrelated content using stale offsets.
- [ ] Handle calls, audio-route changes, headphones disconnecting, app backgrounding, screen locking, and system playback interruptions.
- [ ] Integrate supported lock-screen and headset controls, with the document's title as playback metadata.
- [ ] Coordinate audio-session policy with lecture recording and media playback. Test supported combinations and explain unavailable combinations before starting them.
- [ ] Provide useful recovery for voice downloads, network loss, service errors, quota limits, corrupt audio, missing timing, and expired cached passages.
- [ ] Make buffering and failures distinct from pause and completion. Resume without duplicate or omitted sentences.

## 9. Architecture, storage, and responsiveness

The responsibilities below describe planned boundaries, not existing components or a requirement to introduce a protocol for each responsibility.

- [ ] Keep semantic passage preparation, range policy, source anchors, and mathematical speech mapping in focused Core capabilities.
- [ ] Keep PDF extraction, local speech integration, audio playback, and framework adapters in Apple capabilities with explicit ownership.
- [ ] Keep range selection, visible geometry, temporary highlights, controls, and session composition in UI capabilities.
- [ ] Extend existing Markdown parsing and rendering paths. Avoid a second document model that disagrees with what the user sees.
- [ ] Use typed state for preparation, buffering, speaking, paused, interrupted, failed, and completed transitions.
- [ ] Keep extraction, parsing, recognition, network requests, and audio preparation off the main thread. Apply UI changes on the main actor.
- [ ] Bound passage size, generation concurrency, prefetch depth, memory, and disk caches. Cancel work when the reading target changes.
- [ ] Keep narration audio, recognition transcripts, and alignment caches outside the vault as disposable derived files.
- [ ] Key cached output by document revision, selected content, speech preparation version, voice/model, language, pronunciation settings, and relevant rate settings.
- [ ] Treat rate changes differently for regenerated speech and time-stretched playback. Keep highlight time conversions correct for each path.
- [ ] Provide cache size controls and deletion. Keep user pronunciation preferences and resume choices separate from disposable caches.
- [ ] If audio export is added, make it an explicit save to a standard media format through the existing destination policy. Do not require a narration sidecar to open a note or PDF.
- [ ] Measure time to first speech, seeking delay, memory, battery, and highlight updates on physical iPads. Set budgets after the first measured implementation.
- [ ] Validate long papers and large vaults without whole-vault scans, uncontrolled cloud-placeholder downloads, or preloading the whole textbook.
- [ ] Record dependency purpose, license, pinned version, maintenance status, privacy/storage implications, and unsupported platform capabilities.

## 10. Verification and release checklist

- [ ] Unit-test semantic narration and source mappings using expected spoken passages, including the required Markdown examples above.
- [ ] Test range boundaries, headings, cross-page selections, mathematical endpoints, empty content, and filters that would remove the entire selection.
- [ ] Test PDF extraction against known reading order and visible word positions, including multi-column papers, rotations, ligatures, and repeated headers.
- [ ] Test mathematical speech for grouping and operator fidelity. Track unsupported constructs rather than labeling them complete.
- [ ] Test pause/resume, speed changes, seeking, canceled generations, stale callbacks, chunk joins, and interruption recovery at observable playback boundaries.
- [ ] Test cloud and offline failure paths with real adapter contracts. Do not let a test provider imply timing or cancellation guarantees unavailable in production.
- [ ] Verify temporary highlights and reading preparation leave document contents unchanged, including byte-for-byte checks where applicable.
- [ ] Verify VoiceOver, Dynamic Type, Increase Contrast, Reduce Motion, keyboard navigation, iPhone widths, and iPad multitasking.
- [ ] Verify recording coexistence, Pencil responsiveness, headphone controls, background behavior, and sustained narration on physical devices.
- [ ] Complete the natural-voice listening gate in section 2. Automated tests alone cannot approve human-sounding narration.
- [x] Update `Architecture.md` with implemented boundaries and limitations. Update `Coverage.md` with checks actually run and device work still outstanding.
- [ ] Release only controls backed by working behavior. Keep scanned math, term highlighting, or standalone TeX marked incomplete until their own acceptance checks pass.

## 11. Suggested implementation order

Each increment retains the complete scope above. At the owner's request, finish functional document reading and highlighting before returning to voice quality evaluation.

1. **Voice and document trials:** audition voices with the owner, inspect representative PDFs, validate timing support, and decide provider/cost/offline policy.
2. **Semantic Markdown reading:** implement source-to-speech mapping, natural pauses, exact ranges, playback controls, and temporary word highlighting.
3. **Text PDF reading:** implement page-local extraction, range endpoints, reading order, page highlights, and paper-specific filtering.
4. **Structured mathematics:** add faithful mathematical speech, equation highlighting, detailed mode, and supported term-level mapping.
5. **Daily use and performance:** complete background playback, interruptions, checkpoints, recording coexistence, bounded caches, accessibility, and physical-device listening review.
6. **Difficult documents:** extend scanned text, mathematical recognition, complex layouts, and standalone TeX through separate documented acceptance checks.

## Technical references to verify during implementation

- [Apple speech synthesis](https://developer.apple.com/documentation/avfoundation/speech-synthesis): native utterances, voices, and playback controls.
- [Apple spoken-range callbacks](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate/speechsynthesizer%28_%3Awillspeakrangeofspeechstring%3Autterance%3A%29): notifications for units of speech, generally words, intended for synchronized highlights.
- [Apple PDFPage](https://developer.apple.com/documentation/pdfkit/pdfpage): page text, character bounds, and selections. These APIs alone do not establish scientific reading order or mathematical semantics.
- [ElevenLabs speech with timing](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps): generated audio and character alignment. Check the selected model, alignment availability, pricing, and terms before integration.
- [MathJax accessibility](https://docs.mathjax.org/en/v4.0/basic/a11y-extensions.html) and [Speech Rule Engine](https://github.com/Speech-Rule-Engine/speech-rule-engine): candidates for structured mathematical speech, with integration and coverage still to evaluate.
