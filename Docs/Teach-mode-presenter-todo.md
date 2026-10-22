# TODO: Graphite Teach Mode — Optional Mascot / Presenter

**Status:** Future feature / architecture backlog  
**Created:** 2026-10-12  
**Depends on:** Teach Mode document targeting, lesson timeline, and presentation runtime  
**Scope:** Design an optional animated presenter. This document is a proposal, not an implementation specification verified against the Graphite repository.

## Product intent

Graphite's Markdown note remains the source of truth and the main teaching surface. Teach Mode explains the material while focusing, highlighting, scrolling, and temporarily annotating the existing note. An optional small character participates in that explanation like a professor presenting from slides.

The desired character has friendly, duck-like energy and an original Graphite identity. It can look toward an equation, point at a diagram, move aside before a zoom, or quietly wait while the user reads. Its presence should help attention and comprehension without dominating the page.

**Core requirement: every lesson must remain complete and usable with the character disabled.** Necessary teaching cues must live in narration, captions, or document presentation, never exclusively in a mascot gesture.

## Visual reference and original design

Issue: [#13](https://github.com/Graphite-Note/Graphite/issues/13)

User-provided reference: [ETH shop — Bachelor duck / Badeente Bachelor](https://shop.ethz.ch/en/produkt/badeente-bachelor/).

The attached reference shows a yellow duck with an orange beak, graduation cap, diploma, and ETH Zürich branding. Use its approachable academic personality as inspiration for an original design. The shop page could not be fetched during drafting, so these observations come from the image attached to the original discussion.

- [ ] Develop an original Graphite character with its own silhouette, proportions, expressions, palette, and accessories.
- [ ] Explicitly exclude ETH names, logos, marks, institutional identity, and suggestions of affiliation from the final mascot.
- [ ] Explore a subtle teaching accessory, such as a pointer or pencil, without reproducing the reference duck's complete design.
- [ ] Keep the reference link as design context. Do not ship the shop image as a Graphite character asset.
- [ ] Review the design at its actual small display size in light and dark themes.
- [ ] Keep the renderer independent of the duck so other original characters can be supported later.

## Architecture goals

Issue: [#14](https://github.com/Graphite-Note/Graphite/issues/14)

```text
Markdown note + semantic document model
                  ↓
          Teaching intelligence
                  ↓
      Validated lesson / cue timeline
                  ↓
             Teach runtime
       ┌──────────┼─────────────┐
       ↓          ↓             ↓
 Document /    Narration /   Optional character
 viewport     captions      presentation adapter
 presentation
```

The teaching intelligence plans explanations. The Teach runtime directs playback. The character is an optional actor driven by that runtime.

- [ ] Inspect Graphite's existing editor, document model, rendering, overlays, settings, and audio lifecycle before selecting implementation tools.
- [ ] Keep teaching content, timeline execution, layout decisions, and character rendering separate.
- [ ] Use validated semantic actions and reusable animation states rather than generating character video for each lesson.
- [ ] Make playback deterministic for the same lesson, assets, settings, and layout inputs. Adapt safely when layout changes.
- [ ] Support pause, seek, skip, cancellation, interruption, resume, and immediate character disablement.
- [ ] Keep presentation state temporary and separate from saved Markdown. Ending Teach Mode removes its overlays and character state.
- [ ] Provide a no-character adapter so character availability never blocks document actions or narration.
- [ ] Load character assets only when needed and release animation resources when Teach Mode closes.

### Shared semantic targets

Issue: [#15](https://github.com/Graphite-Note/Graphite/issues/15)

Document and character actions should resolve the same `TargetRef`, scoped to a document revision. Targets may identify a section, equation, equation term, figure, SVG element, native diagram object, or a region inside an image.

The runtime resolves targets into current geometry. The planner should not emit DOM selectors or viewport pixel coordinates. For raster figures, a verified region may use normalized image coordinates tied to that figure. Do not assume a screenshot exposes semantic objects such as a transistor's drain.

- [ ] Define target identity, revision checks, capability discovery, and resolution failures.
- [ ] Transform image regions through crop, scaling, scrolling, and zoom correctly.
- [ ] If a subtarget is unavailable, use a validated parent target or skip the gesture. Never point confidently at an arbitrary location.
- [ ] Revalidate or pause when note edits invalidate the lesson's targets.

## Action namespaces

Start with a small typed vocabulary. Names below illustrate responsibilities and need review against the existing Teach Mode design.

| Namespace | Responsibility | Candidate actions |
| --- | --- | --- |
| `document.*` | Temporary emphasis and annotations on the note | `highlight`, `dim`, `drawArrow`, `reveal`, `restore` |
| `camera.*` | Viewport movement and framing | `focus`, `scrollTo`, `zoomTo`, `pan`, `restore` |
| `character.*` | Optional presenter intent | `enter`, `exit`, `move`, `lookAt`, `pointAt`, `gesture`, `expression` |
| `lesson.*` | Playback and sequencing | `pause`, `wait`, `checkpoint`, `resume` |

The runtime owns execution order and state transitions. Give viewport control one owner rather than implementing competing zoom behavior in both document and camera actions. Define whether a wait ends on time, user input, or completion of a named cue.

### Character action contract

Issue: [#16](https://github.com/Graphite-Note/Graphite/issues/16)

```ts
// Illustrative sketch. TargetRef belongs to the shared document model.
type CharacterAnchor = "bottom-left" | "bottom-right" | "side-gutter" | "auto";
type Gesture = "explain" | "emphasize" | "thinking" | "yes" | "no" | "celebrate";
type Expression = "neutral" | "attentive" | "thoughtful" | "encouraging";

type CharacterAction =
  | { type: "character.enter"; anchor?: CharacterAnchor }
  | { type: "character.exit" }
  | { type: "character.move"; anchor: CharacterAnchor }
  | { type: "character.lookAt"; target: TargetRef }
  | { type: "character.pointAt"; target: TargetRef }
  | { type: "character.gesture"; gesture: Gesture }
  | { type: "character.expression"; expression: Expression };

// Derived from actual narration playback, not a request to generate speech.
type CharacterSpeechState = "speaking" | "silent";
```

The character adapter maps semantic intents onto its supported animations. A minimal implementation might turn, point, and idle. Unsupported optional gestures should resolve to a harmless idle state.

- [ ] Validate action schema, target existence, character capabilities, and bounded durations.
- [ ] Define precedence when pointing, moving, speaking, and gesturing overlap.
- [ ] Keep compulsory document cues independent of optional character cue completion.
- [ ] Treat disabling the character as successful completion or cancellation of its pending cues, preventing timeline deadlocks.
- [ ] Keep asset paths, executable code, and raw renderer commands out of model-generated actions.

## Character behaviors

### Initial useful set

Issue: [#17](https://github.com/Graphite-Note/Graphite/issues/17)

- [ ] Enter and leave quietly, with a small default footprint near a safe corner or gutter.
- [ ] Look toward the currently explained target.
- [ ] Point at a resolved target with a wing or pointer while the document supplies its own highlight.
- [ ] Use restrained explanation and emphasis gestures.
- [ ] Synchronize a simple speaking animation with actual audio playback. Precise phoneme lip sync is optional future polish.
- [ ] Stop speaking immediately when narration pauses, ends, buffers, or is interrupted.
- [ ] Settle into a calm reading/idle pose during pauses and user interaction.
- [ ] Move aside or hide when content needs its space.
- [ ] Offer brief, encouraging quiz reactions without shaming incorrect answers or implying certainty about an unverified answer.

### Later exploration

Issue: [#18](https://github.com/Graphite-Note/Graphite/issues/18)

- [ ] Stand near the edge of a figure, lean toward an equation, or hold a teaching pointer.
- [ ] Visually introduce a temporary explanation panel without changing the note itself.
- [ ] Support alternative original characters through the same action contract.

Avoid constant bouncing, unsolicited interruptions, repetitive celebrations, and idle motion that competes with reading. The character should move for a teaching or layout reason.

## Layout and occlusion handling

Issue: [#19](https://github.com/Graphite-Note/Graphite/issues/19)

Layout decisions belong to the runtime, which has current geometry. A planner may request an anchor, but the runtime can override it to preserve readability.

- [ ] Track the active target, emphasized content, captions, playback controls, editor selection, menus, and other protected regions.
- [ ] Include the character's full animation bounds and pointer sweep in collision checks.
- [ ] Evaluate safe anchors in the viewport and available gutters, with margins from protected regions.
- [ ] Prefer the current safe anchor. Add a minimum dwell time and movement threshold to prevent jitter between corners.
- [ ] Relocate before a camera transition when its destination would cover important content, then resolve pointing geometry after the transition.
- [ ] Recalculate on resize, scroll, zoom, font changes, image loading, sidebar changes, and responsive reflow.
- [ ] If no safe position exists, try a smaller allowed size, then temporarily hide. Keeping the lesson readable takes priority.
- [ ] Keep decorative layers transparent to pointer input so users can select text and interact with the note.
- [ ] If manual placement is supported, treat it as a preference subject to content protection and provide a reset-to-auto control.
- [ ] On pause or interruption, stop stale target gestures and recompute geometry before resuming.

## Settings and accessibility

Issue: [#20](https://github.com/Graphite-Note/Graphite/issues/20)

Character appearance and audio must be independent settings.

| Setting | Proposed behavior |
| --- | --- |
| **Presenter: None** | Narration/captions and document actions continue without a character. |
| **Presenter: Minimal** | Character appears for selected emphasis or interaction cues, then withdraws. |
| **Presenter: Full** | Character accompanies explanations with restrained gestures and automatic relocation. |
| **Voice: Off / AI voice** | Enables or disables spoken narration independently of presenter appearance. |
| **Captions / transcript** | Exposes teaching content in text, including when voice is off. |
| **Reduced motion** | Uses static poses or simple transitions, suppresses walking and decorative loops, and limits viewport motion. |
| **Presenter size / preferred side** | Adjusts appearance within bounds that preserve content visibility. |

- [ ] Choose and document the default presenter mode during product review. Proposed starting default: None, with an explicit opt-in.
- [ ] Allow users to hide the presenter immediately during a lesson and persist their preference.
- [ ] Keep no-character + no-voice mode useful through captions/transcript, readable cue timing, and step controls.
- [ ] Respect system reduced-motion preferences and provide keyboard-accessible playback/settings controls.
- [ ] Keep decorative character elements out of the screen-reader reading order. Communicate essential information through accessible lesson content.
- [ ] Ensure character states and highlights remain distinguishable across themes and without relying only on color.

## Synchronization and interruption

Issue: [#21](https://github.com/Graphite-Note/Graphite/issues/21)

Use the lesson's shared clock and cue system. Narration markers may trigger document and character actions together, while the actual audio lifecycle drives the character's speaking state.

Example teaching beat:

```text
Narration/caption: "Look at the drain side of the transistor."
camera.focus(figure:MOSFET)
document.highlight(figure:MOSFET.drain)
character.lookAt(figure:MOSFET.drain)
character.pointAt(figure:MOSFET.drain)
```

This example requires a resolved drain target. With the character disabled, the same explanation and highlight still execute. Without a validated drain region, fall back to an appropriate whole-figure cue and avoid the precise pointing claim.

- [ ] Cancel in-flight animation on pause, skip, user interruption, and mode changes.
- [ ] Use checkpoints or state reconstruction when seeking. Do not replay every entrance or celebration to rebuild state.
- [ ] When the user asks a question, pause the current lesson, show an attentive pose, and let the Teach runtime manage answering and resuming.
- [ ] Define text-only timing and user-controlled stepping independently of audio availability.

## Non-goals

- Generating a new mascot video for every explanation or using prerecorded MP4 output as the lesson runtime.
- Making a character necessary for understanding or navigating Teach Mode.
- Copying the ETH duck, distributing its shop image as a mascot, or adding ETH branding to Graphite's default character.
- Replacing the note with a separate cartoon stage or allowing character actions to edit saved Markdown.
- Giving the LLM arbitrary UI code execution or direct control over DOM geometry.
- Solving full physics, free-roaming navigation, realistic lip sync, every figure type, or a character marketplace in the first version.
- Coupling voice identity, teaching quality, or lesson generation to the chosen character skin.

## Risks and mitigations

| Risk | Impact | Proposed mitigation |
| --- | --- | --- |
| Occluding equations, labels, captions, or controls | High | Protected regions, full animation bounds, relocation, and hide fallback. |
| Pointing at the wrong target after reflow or edits | High | Revision-aware semantic targets, current geometry resolution, and conservative fallback. |
| Lessons depend on gestures or stall when disabled | High | Independent document/text cues and no-character replay checks. |
| Character and narration drift or continue after interruption | High | Shared clock, actual audio state, cancellation, and checkpoint restoration. |
| Visual similarity or implied institutional affiliation | High | Original design direction, explicit branding exclusions, and asset provenance review. |
| Distraction, motion sensitivity, or patronizing reactions | Medium | Opt-in appearance, Minimal mode, reduced motion, restrained frequency, and user feedback. |
| Animation drains battery or slows long notes | Medium | Lazy loading, bounded assets, stop hidden/off-screen loops, and profile representative devices. |
| Too many actions or renderer-specific lesson schemas | Medium | Small semantic vocabulary, capability negotiation, and adapter boundaries. |

## Phased implementation ideas

### Phase 0 — Inspect and decide

Issue: [#22](https://github.com/Graphite-Note/Graphite/issues/22)

- [ ] Map existing Teach Mode or proposed runtime foundations in the repository.
- [ ] Identify the shared target resolver, overlay host, playback clock, and settings integration points.
- [ ] Compare sprite-based, vector/rigged 2D, and other lightweight rendering options with a tiny disposable spike.
- [ ] Produce original character concepts and a short decision record covering renderer, asset workflow, and initial supported actions.

**Exit:** Agreed boundaries and a feasible asset/rendering approach. No commitment to a large framework before inspection.

### Phase 1 — Deterministic scripted vertical slice

Issue: [#23](https://github.com/Graphite-Note/Graphite/issues/23)

- [ ] Use a placeholder or original draft character with enter, exit, idle, look, and point states.
- [ ] Run a hand-authored lesson over one equation and one figure with stable targets.
- [ ] Add safe corner placement, basic collision handling, a None mode, and cancellation.

**Exit:** The same short lesson works with and without the character, leaves the note unchanged, and never obscures the active target in the supported layouts.

### Phase 2 — Playback, settings, and accessibility

Issue: [#24](https://github.com/Graphite-Note/Graphite/issues/24)

- [ ] Integrate actual narration events, captions, pause/resume, seek, and interruption cleanup.
- [ ] Add None / Minimal / Full, independent voice controls, reduced motion, and preference persistence.
- [ ] Expand layout handling for zoom, reflow, sidebars, captions, and narrow viewports.

**Exit:** Users can hide the character at any moment and complete the lesson without voice or motion.

### Phase 3 — Planner integration and failure handling

Issue: [#25](https://github.com/Graphite-Note/Graphite/issues/25)

- [ ] Expose supported semantic character actions to the teaching planner through capabilities.
- [ ] Validate generated cues and apply safe fallbacks for unsupported actions or missing targets.
- [ ] Coordinate question interruptions and optional quiz reactions through the existing lesson runtime.

**Exit:** Invalid optional cues cannot break playback or produce unverified precise pointing.

### Phase 4 — Polish and evaluate

Issue: [#26](https://github.com/Graphite-Note/Graphite/issues/26)

- [ ] Replace draft assets with the final original Graphite character and consistent animation set.
- [ ] Tune gesture frequency, movement, expressions, and reading pauses using real study sessions.
- [ ] Profile representative long notes and devices, then set measurable asset and frame-time budgets.
- [ ] Consider richer document-edge interactions or a second character only after the first implementation proves useful.

**Exit:** Evidence that the presenter helps users follow explanations, with acceptable distraction and performance.

## Acceptance checklist

Issue: [#27](https://github.com/Graphite-Note/Graphite/issues/27)

- [ ] Disabling the presenter preserves all essential lesson content, playback controls, and document cues.
- [ ] Switching None / Minimal / Full during playback does not restart narration or leave pending cues blocked.
- [ ] Resize, scroll, zoom, and sidebar changes preserve correct target alignment or trigger a safe fallback.
- [ ] No character or pointer overlaps protected content in the supported test scenarios; no safe space results in hiding.
- [ ] Pause, seek, interruption, and resume leave no stale speech, pointing, or duplicate reactions.
- [ ] Voice-off and reduced-motion sessions remain understandable and keyboard accessible.
- [ ] Missing assets, failed renderer initialization, invalid targets, and unsupported gestures degrade gracefully.
- [ ] Exiting Teach Mode clears temporary presentation state and preserves the saved note.
- [ ] Final assets have an original Graphite identity and contain no ETH branding.

## Decisions to revisit before implementation

1. What Teach Mode foundations already exist, and which interfaces should this feature reuse?
2. Which lightweight renderer fits Graphite's platforms, asset workflow, and performance constraints?
3. Which target types can Graphite resolve reliably in the first version?
4. What appearance default and gesture frequency work best in actual study sessions?
5. Should narrow layouts use a reserved presenter area or simply suppress the character when space is scarce?
6. What minimum animation set communicates useful teaching intent without requiring complex lip sync or locomotion?

The first milestone is a small, reversible presenter integration over a working lesson runtime. Richer character behavior should follow reliable targeting, clear teaching cues, and respectful use of document space.
