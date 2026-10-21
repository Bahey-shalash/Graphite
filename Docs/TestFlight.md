# Releasing to TestFlight

The iOS app is listed in App Store Connect as **Graphite Note** (the names "Graphite" and "Graphite Notes" were taken), with bundle identifier `com.graphite.study`, SKU `graphite`, and team `JDP856P5D5`. The App Store name is what TestFlight shows; on the device the app is still called Graphite (`CFBundleDisplayName`). The record lists iOS and macOS. Its "iPhone and iPad Apps on Apple Silicon Macs" setting is off (2026-10-20), so a Mac gets the native Mac build, never the iPad one.

## Uploading a build

```bash
scripts/archive-for-testflight.sh /tmp/graphite-testflight
```

```bash
scripts/archive-for-testflight.sh /tmp/graphite-testflight --macos
```

The script archives the `Graphite` scheme in Release for `generic/platform=iOS`, or `generic/platform=macOS` with `--macos`, and uploads it with `App/ExportOptions.plist` (method `app-store-connect`, automatic signing). The checkout sits in iCloud's Desktop, where codesign fails, so the folder it is given must be outside it. Xcode must be signed in to the team's Apple account. `--archive-only` stops before the upload. It refuses to start while another build or test run is going, because parallel builds starve the machine.

Each upload needs a higher build number than the last. The script passes the date and time (`20261020.1530`) as `CURRENT_PROJECT_VERSION`, which `Info.plist` reads as `CFBundleVersion`; nothing in the repository changes per upload. The version people see is `MARKETING_VERSION` in the project (1.0). Raise it for a new release. Both are project-level build settings, so the share extension always carries the same version and build number as the app, which App Store Connect requires of an embedded extension.

## The share extension and its App Group (2026-10-21)

The iOS and iPadOS app embeds a share extension, target `GraphiteShareExtension`, bundle identifier `com.graphite.study.share`, and both are signed with the App Group `group.com.graphite.study` (`App/Graphite-iOS.entitlements`, `ShareExtension/ShareExtension.entitlements`). Before this the iOS app was signed with no entitlements file at all. Signing stays automatic with team `JDP856P5D5`. The Mac app is unchanged: its entitlements (`App/Graphite.entitlements`) have no App Group and the extension is not built or embedded for macOS (the target dependency and the embed carry a platform filter for iOS), so `--macos` uploads need nothing new.

**Before the next iOS archive, once:** the App Group and the extension's App ID must exist on the developer account. Do either of these:

1. In Xcode, signed in to the team's account: open `Graphite.xcodeproj`, select the target **Graphite**, tab **Signing & Capabilities**, iOS. **App Groups** shows `group.com.graphite.study`; if it has a red mark or "Register", click the refresh button or the group's checkbox so Xcode registers it and turns App Groups on for `com.graphite.study`. Do the same for the target **GraphiteShareExtension**, which also makes Xcode register the App ID `com.graphite.study.share`. Both targets must show no signing error.
2. Or at developer.apple.com › Certificates, Identifiers & Profiles › Identifiers: add an **App Group** `group.com.graphite.study`; edit the App ID `com.graphite.study`, turn on **App Groups** and assign that group; add an App ID `com.graphite.study.share` (explicit) with **App Groups** on and the same group.

Then run `scripts/archive-for-testflight.sh` as before. The script needs no change: it archives the `Graphite` scheme, which builds and embeds the extension, and `-allowProvisioningUpdates` with automatic export signing creates the distribution profiles of both bundle identifiers. Nothing changes in App Store Connect; the extension ships inside the app. If the archive stops with "No profile for team … matching 'com.graphite.study.share'" or "Provisioning profile doesn't include the com.apple.security.application-groups entitlement", the step above was not done. None of this was tried from the session that added the extension: it built the app and the extension for the simulator only, where no profile is needed.

The extension has its own privacy manifest, `ShareExtension/PrivacyInfo.xcprivacy`: file timestamps in the app's containers (`C617.1`), for the share inbox in the App Group. `ShareExtensionDeclarationsTests` checks the group, the entitlements, the extension point and the versions.

Xcode's Organizer works too (Product › Archive, then Distribute App › TestFlight & App Store), but it uses build number 1 from the project unless it is raised by hand.

## What the upload declares

- `LSApplicationCategoryType` is Productivity: App Store Connect refuses a Mac build without a category, and iOS ignores it.
- `ITSAppUsesNonExemptEncryption` is `false` in `App/Info.plist`: Graphite only uses HTTPS and Apple's own cryptography, so builds skip the export compliance question.
- `App/PrivacyInfo.xcprivacy` declares no tracking and no collected data, and the reasons for the APIs Apple asks about: UserDefaults (`CA92.1`, the app's own settings), file timestamps (`C617.1` and `3B52.1`, files in the container and in the vault the person chose), time since boot (`35F9.1`, measuring elapsed time) and free disk space (`E174.1`, checked before a recording is written). Packages bring their own manifests (GRDB, swift-crypto). Update it when code starts using another API in Apple's required-reason list.

`InfoPropertyListDeclarationsTests` checks these values and that the manifest is copied into the app.

## Testers

Internal testers (members of the App Store Connect team, up to 100) can install a build once processing finishes. External testers (by email or a public link) need Beta App Review for the first build of a version; the community plugin runtime, which runs JavaScript the person downloads, may draw questions under guideline 2.5.2.
