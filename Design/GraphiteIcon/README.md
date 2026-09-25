# Graphite icon design

The app ships five icon presets, listed under Bundled icon presets below, with blue as the default. All of them come from `Graphite-MatteStylus.icon`, the approved paper and pen design. Open it in Apple Icon Composer. It shows a glass note pointing toward 10–11 o’clock, a shorter, slimmer raised matte graphite stylus with a narrow blue side accent, a `.md` label, and handwritten strokes on a pearl background. `Graphite-CharcoalInk.icon` (neutral charcoal) and `Graphite-BlueGraphiteInk.icon` (muted blue graphite) are two ink options made from it with the built-in image-editing tool; both match the handwriting and `.md` label to their pencil-tip color, and their edit prompts are in `Ink-Options-Prompts.txt`. The earlier silver-pen version is preserved in `Graphite-Refined.icon`.

The foreground is one transparent PNG generated with the built-in image-generation tool. The glass, handwriting, and stylus are rendered together, so their component shapes and lighting are not separately editable native layers. The Icon Composer background, foreground placement, scale, and group settings remain editable. The glass appearance in this draft is primarily rendered in the image, not a claim of separate native dynamic refraction for each object.

The source image is inside `Graphite-MatteStylus.icon/Assets/GlassNoteAndStylus.png`. The original generation prompt is in `Refined-Artwork-Prompt.txt`; the pen-only edit prompt is in `Matte-Stylus-Edit-Prompt.txt`. The paper was held as the visual reference during the edit; pixel-identical preservation has not been measured. Earlier vector designs remain alongside this draft for reference and are superseded.

## Bundled icon presets

The application now consumes the Icon Composer documents in `../../App/Icons/`:

| Choice | Document | Ink/tip color reference |
| --- | --- | --- |
| Blue (default) | `AppIcon.icon` | User's RGB 48, 104, 232 / `#3068E8` |
| Red | `AppIconRed.icon` | `#C9434D` |
| Black | `AppIconBlack.icon` | `#15171B` |
| Charcoal | `AppIconCharcoal.icon` | `#292E35` |
| Blue graphite | `AppIconBlueGraphite.icon` | `#3B4D60` |

Blue, red, and black were edited with the built-in image tool from the approved matte-stylus foreground; prompts are preserved in `App-Icon-Preset-Prompts.json`. These are rendered color references, not measurements of every shaded pixel. Charcoal and blue graphite reuse the preceding options. All documents retain the pearl light background, dark background specialization, and foreground placement. The pen's narrow blue side accent stays blue.

On iPhone/iPad, choose Settings → Appearance → App icon. Xcode compiles these documents and registers their names as primary/alternate icons. Settings previews live in `../../App/IconPreviews.xcassets`; update their foreground copies whenever the icon artwork changes. These previews approximate the light appearance. macOS uses the default blue icon; the picker is iOS-only.

Earlier design-only documents above remain available for comparison. See `../../Docs/Coverage.md` for build and runtime verification and outstanding device checks.
