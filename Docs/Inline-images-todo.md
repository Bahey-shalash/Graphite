# Images side by side on one line: implementation TODO

Created: 2026-10-24.

Status: not started. Issue: [#102](https://github.com/Graphite-Note/Graphite/issues/102) (section 1).

## Request

The owner, 2026-10-24, with screenshots of the note "Butter-basted steak.md": "![] are not showing properly". Its Photos section writes several image embeds on one line, as Obsidian users do to put photos side by side:

```
![[IMG_3599.jpg|300]] ![[IMG_3598.PNG|200]]

![[IMG_6652.JPG|250]] ![[IMG_6653.JPG|250]] … ![[IMG_6661.JPG|250]]
```

Graphite shows each as link-colored text, `IMG_3599.jpg|300`, the width included, wrapping in the middle of a name (`IMG_6656.JPG|` / `250`). Obsidian shows the images, each at its width, side by side and wrapping to the next row.

## What exists today (2026-10-24)

- Live Preview draws an embed as an image only when it is alone on its line: `EmbedLocator.standaloneEmbed(onLine:)` (`Sources/GraphiteCore/EmbedLocator.swift`, called from `Sources/GraphiteCore/LivePreviewBlocks.swift`). Any other embed is styled like a link (`MarkdownTextStyler`, `case .link, .embed`): its `![[` and `]]` are hidden, its target and size stay as text.
- Reading view already turns a resolved inline image embed into an inline image (`prepared` in `Sources/GraphiteUI/MarkdownPreview.swift`, drawn by `VaultImageLoader` / `VaultImageAttachment` with `EmbedDisplaySize`); an embed the index has not resolved yet is shown as a link until it does.

## 1. Draw inline image embeds as images

Issue: [#102](https://github.com/Graphite-Note/Graphite/issues/102)

- [ ] Live Preview draws an image embed that shares its line with text or other embeds as an inline image at its size (`|300`, `|300x200`), images side by side and wrapping to the next row as in Obsidian; wiki (`![[a.jpg|300]]`) and Markdown (`![300](a.jpg)`) forms alike, any extension case (`.JPG`, `.PNG`).
- [ ] The size suffix and the file name never show as text; the cursor on an embed shows that embed's source only, as today for the first one in the screenshot.
- [ ] Reading view checked with the same note: every image of the Photos section drawn, none left as a link once the index has read the vault.
- [ ] Inline images in table cells, list items and callouts drawn the same way in both views.
- [ ] Thumbnails decoded off the main actor at their displayed size, through the existing image cache, so a row of ten 250-point photos scrolls without slow frames and without decoding the full camera images.
- [ ] Tests: Core tests that a line of several embeds yields inline image ranges with their sizes; hosted tests that Live Preview and reading view draw two side-by-side embeds as image attachments, not link text.
- [ ] Checked on the Mac and the iPad with the owner's "Butter-basted steak.md".
