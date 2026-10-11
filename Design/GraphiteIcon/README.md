# Graphite icon design

The app ships five icon presets, listed under Bundled icon presets below, with blue as the default. Since 2026-10-10 all of them are the graphite crystal: a hexagonal column with a long point above and a short one below, seen with one face toward the viewer and a little from above, leaning to the right, in steel grays with a colored sheen on the front facets, on a pearl background. It is a sibling of Obsidian's purple crystal, as Graphite is a sibling of Obsidian, and one simple shape, as Apple's app icon guidance asks; the owner chose it after finding the earlier glass note and stylus too detailed to be iconic.

The source is `GraphiteCrystal/make_graphite_crystal_icon.py`. Run it from the repository root (`python3 -I Design/GraphiteIcon/GraphiteCrystal/make_graphite_crystal_icon.py`; it needs Pillow and NumPy). It writes each preset's Icon Composer document in `../../App/Icons/` (an `icon.json` and one SVG per facet, nine flat shapes with a gradient each) and its Settings preview in `../../App/IconPreviews.xcassets/` (the crystal alone, transparent around it). Because the facets are separate vector layers, the system draws the glass, specular highlights, shadow and the dark, clear and tinted appearances itself; nothing of the kind is painted into the artwork. Change the crystal's shape, colors or presets in the script and run it again rather than editing the generated files. The documents open in Icon Composer for a look at the appearances.

Checked on the iPad simulator's Home Screen and Dock beside Apple's icons, where the compiled icon shows the system's glass edges.

## Bundled icon presets

| Choice | Document | Sheen |
| --- | --- | --- |
| Blue (default) | `AppIcon.icon` | Ink blue, `#2D5DA1`, the app's default accent |
| Red | `AppIconRed.icon` | `#C9434D` |
| Black | `AppIconBlack.icon` | None: the crystal in steel grays |
| Charcoal | `AppIconCharcoal.icon` | None, with every facet darker |
| Blue graphite | `AppIconBlueGraphite.icon` | `#3B4D60` |

On iPhone and iPad, choose Settings › Appearance › App Icon. Xcode compiles these documents and registers their names as primary and alternate icons. macOS uses the default blue icon; the picker is iOS-only.

## Earlier designs

The documents in this folder are earlier designs, kept for comparison: the glass note with a matte stylus that shipped from 2026-09-23 to 2026-10-10 (`Graphite-MatteStylus.icon`, one PNG generated with an image tool, with the glass, handwriting and stylus rendered together; its prompts are in `Refined-Artwork-Prompt.txt`, `Matte-Stylus-Edit-Prompt.txt`, `Ink-Options-Prompts.txt` and `App-Icon-Preset-Prompts.json`), its ink options (`Graphite-CharcoalInk.icon`, `Graphite-BlueGraphiteInk.icon`), the silver-pen version (`Graphite-Refined.icon`), and the vector designs before them. See `../../Docs/Coverage.md` for verification.
