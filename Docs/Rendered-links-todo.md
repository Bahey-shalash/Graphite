# Links in rendered Markdown follow at the first tap: TODO

Created: 2026-10-22.

Status: open. Issues: [#80](https://github.com/Graphite-Note/Graphite/issues/80) (section 1), [#81](https://github.com/Graphite-Note/Graphite/issues/81) (section 2).

## Request

Found on 2026-10-22 while building hover previews of links (Community plugins, issue #52); the defect predates that work. On the iPad, a tap on a link in rendered Markdown sometimes follows nothing. With a vault of `Start.md` ("Read about [[Lausanne]] and [[Geneva#Old town]]"), `Lausanne.md` (a link to `[[Geneva]]` and about forty paragraphs) and `Geneva.md` (headings Old town and Lake): open Lausanne in Live Preview, switch to the reading view with the pencil, tap "Geneva", and nothing happens. Open and close Settings, tap again, and the link is followed. The same defect makes links inside Page Preview's card (`LinkPreviewCard`, on the branch `plugin-hover-previews`) follow nothing every time.

## Cause

With text selection on, a tap on rendered text reaches Textual's text interaction view (`UITextInteractionView` on the iPad, `NSTextInteractionView` on the Mac), which asks its `TextSelectionModel` for the link under the tap. The model received the text's layouts through `onChange`, and SwiftUI runs an `onChange` action at most once per frame ("onChange(of: AnyTextLayoutCollection) action tried to update multiple times per frame"). A text's layouts change several times in the frame it first appears in, since each fragment is an empty `Text` until its `TextBuilder` exists, so the model kept the empty layouts: no lines, no link. Anything that laid the text out again later (Settings opening and closing) gave the model the real layouts. `BUG-READING-06` in `Docs/solid/defects.md`.

## Decisions

- Fixed in the vendored Textual (`Vendor/textual/GRAPHITE-PATCHES.md`, patch 20), where the defect is, so every selectable rendered text gets the fix: the reading view, Live Preview's rendered blocks, embeds, canvas cards and Page Preview's card. The same change is proposed upstream in gonzalezreal/textual#71.
- The layouts reach the model through a hidden platform view's update, which SwiftUI calls at every update; `.task(id:)` is built on `onChange` and has the same limit. A view update must not change observed state (`FR-08`), so carrying a selection over to new layouts updates the stored range without notifying observers.

## 1. A tap on a link follows it as soon as the text shows

- [x] The selection model takes every layout of the text (Textual patch 20).
  Done 2026-10-22: `UIKitTextLayoutModelUpdater` and `AppKitTextLayoutModelUpdater` (new, hidden views) pass each layout collection to the `TextSelectionModel` from their `update…View`, in place of `TextSelectionInteraction`'s `onChange`; carrying a selection over to new layouts updates the stored range without notifying observers, and the coordinator's list of models is not observed. Logged in the iPad simulator before the fix: the overlay received 41 layouts with lines while the model kept 41 without, with SwiftUI's "onChange(of: AnyTextLayoutCollection) action tried to update multiple times per frame"; with the fix that message is gone. `.task(id:)` was tried first and has the same limit. Package tests on macOS: `AppProjectTextualPatchTests`, `UiReadingViewTests`, `UiReadingTaskTests`, `UiNumberedEquationTests`, `ReadAloudReadingViewTests`, `UiStylingFixTests`, `UiLivePreviewEmbedContinuityTests` (97, all passing). Hosted iPad (iPad Pro 11-inch (M5) simulator, iOS 27.0): `ReadingLinkFollowingTests`, `ReadingTasksAndEquationsTests`, `LivePreviewBlockPlacementTests`, `LivePreviewRevealTests`, `EditingContinuityTests`, `CodeHighlightingTests`, `PDFLinkFollowingTests` (51, all passing).
- [x] A regression test that fails without the patch.
  Done 2026-10-22: hosted `ReadingLinkFollowingTests.testTapOnALinkRightAfterSwitchingFromLivePreviewFollowsIt` opens the request's Lausanne in Live Preview, switches with the pencil's action and taps the link through UIKit's event path (`SynthesizedTouches`); without the patch it times out waiting for Geneva, with it Geneva opens. Opening the note straight in the reading view failed the same way before the patch. No package test shows the defect: on the Mac, a selectable text hosted in a window, alone or as the reading view's text, with one paragraph or forty, has its layouts in one update.
- [ ] Checked by hand in the iPad simulator, with the request's vault.

## 2. Checks still to make

- [ ] Page Preview's card: links in `LinkPreviewCard` follow once the branch `plugin-hover-previews` has this patch.
- [ ] The Mac app's reading view: a click on a link right after switching from Live Preview, and selecting text while the window is resized. The patch changes the AppKit path too; the package tests of Textual and the reading view pass, but no package test shows the defect on the Mac, and a development build of the Mac app opens the owner's vault, so it is not checked by hand here.
- [ ] A physical iPad: the request's steps, and selecting text in the reading view, then rotating.
