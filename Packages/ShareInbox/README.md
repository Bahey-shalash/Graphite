# ShareInbox

The folder in which an app's share extension leaves shared items for the app, and the list of vaults the app publishes for the extension. Graphite's share extension writes items here; the app moves them into a vault the next time it is opened or becomes active.

An extension cannot reach the folders the app was given (security-scoped bookmarks belong to the app), so the two exchange ordinary files through an App Group container:

```
<container>/Share Inbox/<identifier>/item.json        the description (SharedItemManifest)
                                    /Note.md          the shared text, as Markdown
                                    /Attachments/...  the shared files
                                    /delivery.json    what the app has done so far (SharedItemDeliveryRecord)
<container>/Share Inbox/.drafts/<identifier>/         an item the extension is still writing
<container>/Known Vaults.json                         the vaults the app knows (SharedVaultList)
```

- An item is written under `.drafts` and renamed into the inbox when complete, so a reader never sees half of one.
- Descriptions are JSON with ISO 8601 dates, sorted keys and pretty printing. `formatVersion` is 1; an item of a later version is listed as unreadable and left alone. A destination this build does not know is kept as `unknown(raw)`.
- `delivery.json` lets a delivery that stopped halfway resume without copying a file or writing a note twice.
- Description files are read up to 1 MiB, `Note.md` up to 8 MiB. Attachment names are single plain file names (`SharedAttachmentName`), so a description cannot point outside its item.

The package imports Foundation only and knows nothing of Graphite: applying an item to a vault is Graphite's (`SharedItemDelivery` in GraphiteCore). It never writes into a vault.

Tests: `swift test --package-path Packages/ShareInbox`.
