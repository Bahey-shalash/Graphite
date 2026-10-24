# Map view: center on where I am: implementation TODO

Created: 2026-10-24.

Status: not started. Issue: [#100](https://github.com/Graphite-Note/Graphite/issues/100) (section 1).

## Request

The owner, 2026-10-24, about the Map view: "ya pas la localisation genre ça ce focalise pas" (there is no location, it doesn't focus). The map never shows where the person is and never centers on them.

## What exists today (2026-10-24)

- `VaultMapScreen` and `LocalMapPanel` (`Sources/GraphiteUI/MapViews.swift`) draw notes through `NotesMapView` (`Sources/GraphiteUI/NotesMapView.swift`). Its camera only ever frames the notes (`placeCamera`, again on Show All); it never sets `showsUserLocation` and offers no "my location" control.
- A Bases map (`BaseMapView`, `BaseTiledMapView`) without markers or a configured center opens on latitude 0, longitude 0 (`cameraTarget` in `Sources/GraphiteUI/BaseMapView.swift`), in the Atlantic.
- The app asks for no location access: `App/Info.plist` has no `NSLocationWhenInUseUsageDescription`, and `App/Graphite.entitlements` has no `com.apple.security.personal-information.location` for the sandboxed Mac app, so even a user-location button could not work today.

## 1. Show and center on the person's location

Issue: [#100](https://github.com/Graphite-Note/Graphite/issues/100)

- [ ] A "my location" control on `VaultMapScreen`, `LocalMapPanel` and Bases maps (MapKit's own user-tracking button where it exists, `MKUserTrackingButton` on iPad and iPhone, the equivalent on the Mac), placed in an existing bar or as a map control, not a new row above the map.
- [ ] Location access is asked for only when the person first taps that control (when-in-use, never always), with a usage description saying the map centers on them and nothing is stored or sent; nothing about location runs while the control is unused, so the map costs nothing more when it is off.
- [ ] Tapping it shows the person's position on the map and centers on it; Show All still frames the notes, and the camera stays where the person moved it otherwise.
- [ ] A Bases map without markers or a configured center opens on the person's position when access was already granted, else on the vault's notes, not on 0, 0.
- [ ] Refused or restricted access: the control explains how to turn it on in Settings and the map keeps working without it.
- [ ] `NSLocationWhenInUseUsageDescription` in `App/Info.plist`, the location entitlement for the Mac app, and `App/PrivacyInfo.xcprivacy` updated if it needs to list it.
- [ ] Check while there: the vault map frames every placed note when it opens on the iPad and the iPhone (the owner's "ça se focalise pas" may also mean this), with the owner's vault.
- [ ] Tests: hosted tests that the control exists on each map, that the camera target without markers is no longer 0, 0 when a position is known, and that no location request is made before the control is used.
- [ ] Checked on the iPad, the iPhone and the Mac: first-use permission prompt, centering, refusal.
