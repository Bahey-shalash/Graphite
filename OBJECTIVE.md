# Graphite: product objective

Graphite is a native Apple Pencil-first knowledge and study app that gives an Obsidian vault the notebook and PDF capabilities of Goodnotes without giving up open files.

It is an iPad-first application, designed for study, lectures, handwriting, and knowledge management. Its architecture also supports macOS and iPhone where the platform and interaction model make sense. It should feel like one coherent native application.

## The user's files are the product

An ordinary folder is a Graphite workspace. It may already be an Obsidian vault. Graphite opens and edits that folder directly. The filesystem is authoritative.

If Graphite disappeared, users must still be able to read their work with Obsidian, Finder, Files, Preview, normal Markdown applications, image viewers, PDF readers, and media players.

Use ordinary formats:

| Content | Authoritative format |
| --- | --- |
| Notes, properties, links, and written knowledge | Markdown `.md` |
| Handwritten notebooks, lecture slides, and annotations | PDF `.pdf` |
| Handwritten regions embedded in Markdown | PNG `.png` (exact appearance), or vector PDF `.pdf` or SVG `.svg`, chosen by the user |
| Images and attachments | Their existing standard file formats |
| Lecture audio | M4A `.m4a` |
| Lecture video | MP4 `.mp4` |
| Database views of notes | Obsidian Bases `.base` (YAML) |

Do not invent a Graphite document extension. Do not require annotation or Pencil sidecars. Never make an application database the only representation of user content. Search indexes and thumbnails are disposable derived data stored outside the vault.

## The unified study workflow

A student can open a course folder, write a Markdown note, insert a Pencil derivation at the cursor, annotate lecture slides, insert handwritten pages into the same PDF, and record a lecture while moving between documents. Later they can reopen the same ordinary files in Graphite or another compatible application.

Like Obsidian, Graphite remembers several vaults and switches between them from the sidebar, returning to the document last open in each. The sidebar reflects the real vault hierarchy. Each file opens into an appropriate native editor or preview. Toolbars adapt to the current document. Recording persists independently of document navigation. Touch, Pencil, keyboard, trackpad, accessibility, orientation changes, and multitasking are first-class interactions.

## Markdown and knowledge management

Markdown is a first-class editing environment. Preserve Obsidian-compatible headings, lists, tasks, tables, code, math, callouts, block quotes, tags, frontmatter, aliases, relative links, Wikilinks, and embeds. Existing notes must not be rewritten simply because Graphite opens or indexes them.

Support full-text and filename search, backlinks, outgoing and unresolved links, headings, tags, aliases, attachment insertion, link completion, internal navigation, recent documents, and a command/search interface.

Offer Obsidian's reading view, Live Preview, and source mode, and the built-in features Obsidian ships with that fit the platform: properties, Bases with table, cards, list, and map views, outline, backlinks, outgoing links, tags, and word count. Like Obsidian's core plugins, each feature can be switched off. The Colors plugin syntax (`~={#hex}text=~`) is built in as one of those features and stays ordinary text in the note.

Respect relevant `.obsidian` settings, particularly attachment locations: vault root, configured directory, the current note's directory, or a subdirectory relative to that note. Keep this policy isolated from editor code.

## Pencil drawings in Markdown

Inserting a drawing opens a full-screen canvas. The canvas keeps a fixed width, matching the width limit of a Markdown note, and grows downward as the user writes. Saving creates an ordinary file in the resolved attachment location and places a normal embed at the insertion point, for example `![[ADC architecture.png]]`. Cancelling creates nothing.

The user chooses the file format, with a default in settings:

- PNG keeps the exact look of every PencilKit brush. Optional versioned metadata inside a valid private ancillary PNG chunk preserves the drawing for re-editing.
- PDF and SVG store the ink as vector outlines that stay sharp at any zoom. Brush texture is simplified. PDF keeps re-editing data in its standard XMP metadata stream; SVG keeps it in a standard `<metadata>` element.

PencilKit provides stroke capture, native tools, erasing, selection, undo/redo, and supported Pencil interactions. Every format contains the complete visible drawing. A normal image viewer, PDF reader, or browser must never require Graphite metadata. When another application changes the visible drawing, or removes the metadata, Graphite detects it: stroke-level editability is lost, the visible content stays intact. Ordinary PNG, PDF, and SVG files remain ordinary files.

## One PDF notebook system

A notebook is a PDF. Blank, dotted, grid, ruled, Cornell, engineering, and custom paper become actual PDF page content. The same system handles notebooks, imported slides, textbook chapters, worksheets, and scans.

Provide thumbnail overview, page insertion, duplication, deletion, reordering, rotation, multiple selection, importing and exporting pages, bookmarks, and available outlines. Paper sizes and orientation are customizable.

Use PDFKit and per-page Pencil interaction layers. Store visible annotations inside the PDF using standard annotation mechanisms. Optional embedded Graphite editing metadata must never be necessary to render the annotations. Avoid a separate notebook engine or annotation sidecars.

## Lecture recording

Recording is a session-level feature. Users can start, pause, resume, stop, and monitor elapsed time while writing, drawing, changing pages, or navigating the vault.

Use AVFoundation and ordinary media files. Support permission handling, interruptions, route changes, appropriate background behavior, meaningful names, destination/course context, playback, and seeking. Design note-to-recording timestamps so they can be added without introducing a proprietary media container.

## Safety and interoperability

Use security-scoped folder access and coordinated, atomic file operations. Detect external edits and provider conflicts. Never silently overwrite another application's changes or discard unsaved user work. Respect existing paths, names, attachments, and organization.

Test outputs with independent standard decoders and viewers. Editable enhancements may degrade when another application removes them. Visible content must remain portable.

## Scale and responsiveness

Design for 10,000 and 100,000 notes or attachments, large PDFs, long recordings, and large images. These are validation workloads, not unmeasured performance claims.

Opening a document must not wait for a full vault scan. Keep discovery, indexing, rendering, saving, and recording independent. Use incremental indexing, bounded queries and caches, lazy navigation, per-page rendering, cancellation, and background work. Never keep the entire vault's content or every PDF page in memory. Cloud placeholders must not trigger an uncontrolled download of the whole vault.

Measure latency, memory, and responsiveness on representative physical iPads, including while recording and writing with Pencil. Architecture must retain the ordinary-file model as it scales.

## Product scope and future compatibility

Do not redefine Graphite as an MVP, prototype, or demonstration to avoid core requirements. Implementation is incremental, but the architecture represents the complete intended product. Track incomplete work honestly and keep it in scope. No fake features, inert buttons, or TODO-only implementations presented as complete.

Future Obsidian plugin compatibility is desirable but is not the current priority. Preserve file and syntax compatibility now. Investigate a later extension boundary without inheriting a main-thread plugin runtime or proprietary storage model. Do not promise unchanged execution of plugins that require Electron, Node.js, or Obsidian internals.

## Definition of success

A student can use Graphite as their primary iPad Markdown, handwriting, PDF, and lecture study environment. They retain a normal Obsidian-compatible vault, including complete visible drawings, annotated PDFs, and playable recordings. Graphite earns adoption through its editing experience and performance, never through lock-in.
