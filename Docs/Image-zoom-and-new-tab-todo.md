# Zoom into images and open them in a new tab: implementation TODO

Created: 2026-10-22.

Status: not started. Issues: [#76](https://github.com/Graphite-Note/Graphite/issues/76) (section 1), [#77](https://github.com/Graphite-Note/Graphite/issues/77) (section 2).

## Request

The owner, 2026-10-22: "Faut implementé le zoom in et le open in a new tab pour les images … specially in tables if you want to open a image to see it clearer by just zooming in (same window) or opening the image in a new tab, its really annoying right now." The screenshot shows the reference: a small magnifier button over an image with the tooltip "Zoom in".

So every image shown in a note offers two things, wherever it sits (its own line, inside a table cell, inline in a sentence, in a callout or an embedded note):

- **Zoom in**: look at the image larger without leaving the note.
- **Open in new tab**: open the image file as its own workspace tab, next to the note.

## What exists today (2026-10-22)

- An image on its own line in Reading view or Live Preview (`ReadingImageBlock` in `Sources/GraphiteUI/MarkdownPreview.swift`, the image widget in `Sources/GraphiteUI/LivePreviewWidgets.swift`) has a View action: on iPad and iPhone it sets `workspace.viewedImage`, which shows `ImageViewer` full screen (pinch and double-tap zoom, `ZoomableImageView` in `Sources/GraphiteUI/FilePreviewPane.swift`); on the Mac it opens Quick Look (`GraphiteRootView.swift`). Both cover the whole window instead of zooming in place, and neither offers a new tab.
- An image inside a table cell or inline in text is a text attachment (`VaultImageLoader` / `VaultImageAttachment` in `MarkdownPreview.swift`). It has no tap, hover or context-menu action at all: it can't be enlarged or opened. This is the case the owner hits most.
- Opening a file in a new tab already exists for vault entries (`VaultEntryAction.openInNewTab`, `workspace.open(_:placement: .newTab)`), and an image file opened that way shows in `FilePreviewPane`.

## 1. Zoom into an image in place

- [ ] A zoom control on every rendered image, block and inline alike, including images in table cells: a magnifier button that appears on pointer hover (Mac, iPad trackpad) and Pencil hover, and a long-press / context-menu "Zoom In" item on touch.
- [ ] Zoom happens in the same window over the note, as in the owner's reference screenshot of 2026-10-24 (Obsidian's image zoom): a "Zoom" magnifier button with its tooltip at the image's top-right corner, then the image fitted to the whole window over a black backdrop with the app dimmed behind it, the file name centered at the top and a close button at the top-right. Not a separate full-screen cover or Quick Look window. Pinch, double-tap and scroll-wheel/trackpad zoom, drag to pan, Escape, a tap outside or the close button returns to the note at the same scroll position.
- [ ] The zoomed image is decoded at a resolution fit for the zoom level (the table cell thumbnail is too small to enlarge), with the existing `ImageFileService.displayImage(at:maximumPixelDimension:)` bound so huge images don't spike memory.
- [ ] Works in Reading view and Live Preview, in tables, callouts, embedded notes and canvas cards; Draw on Image stays reachable from the zoomed view where it is today.
- [ ] Tests: hosted tests that an image in a table cell and an inline image expose the zoom action and present the zoomed view; a check that the note's scroll position survives zooming in and out.
- [ ] Checked on the iPad (finger, Pencil hover, trackpad) and on the Mac (pointer, trackpad pinch, Escape).

## 2. Open an image in a new tab

- [ ] "Open in New Tab" on every rendered image (same places as section 1): in the hover controls next to the magnifier, and in the long-press / context menu, alongside "Open on Other Side" where split panes exist.
- [ ] The tab shows the image file through the existing image tab (`FilePreviewPane`), zoomable, with the image's file name as the tab title; the note's tab stays open and unchanged.
- [ ] Command-click (Mac, iPad keyboard) on an image opens it in a new tab directly, as for links.
- [ ] Images outside the vault (web URLs) either open in a tab that shows them or offer only Zoom In; never a broken tab.
- [ ] Tests: hosted tests that the action on a table-cell image and a block image calls `workspace.open(_:placement: .newTab)` with the image's vault path, and that a web image doesn't.
- [ ] Checked on the iPad and the Mac with the owner's table-heavy notes.
