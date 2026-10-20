# Releasing to TestFlight

The iOS app is listed in App Store Connect as **Graphite Note** (the names "Graphite" and "Graphite Notes" were taken), with bundle identifier `com.graphite.study`, SKU `graphite`, and team `JDP856P5D5`. The App Store name is what TestFlight shows; on the device the app is still called Graphite (`CFBundleDisplayName`). The record lists iOS and macOS; only the iOS build is uploaded so far.

## Uploading a build

```bash
scripts/archive-for-testflight.sh /tmp/graphite-testflight
```

The script archives the `Graphite` scheme in Release for `generic/platform=iOS` and uploads it with `App/ExportOptions.plist` (method `app-store-connect`, automatic signing). The checkout sits in iCloud's Desktop, where codesign fails, so the folder it is given must be outside it. Xcode must be signed in to the team's Apple account. `--archive-only` stops before the upload. It refuses to start while another build or test run is going, because parallel builds starve the machine.

Each upload needs a higher build number than the last. The script passes the date and time (`20261020.1530`) as `CURRENT_PROJECT_VERSION`, which `Info.plist` reads as `CFBundleVersion`; nothing in the repository changes per upload. The version people see is `MARKETING_VERSION` in the project (1.0). Raise it for a new release.

Xcode's Organizer works too (Product › Archive, then Distribute App › TestFlight & App Store), but it uses build number 1 from the project unless it is raised by hand.

## What the upload declares

- `ITSAppUsesNonExemptEncryption` is `false` in `App/Info.plist`: Graphite only uses HTTPS and Apple's own cryptography, so builds skip the export compliance question.
- `App/PrivacyInfo.xcprivacy` declares no tracking and no collected data, and the reasons for the APIs Apple asks about: UserDefaults (`CA92.1`, the app's own settings), file timestamps (`C617.1` and `3B52.1`, files in the container and in the vault the person chose), time since boot (`35F9.1`, measuring elapsed time) and free disk space (`E174.1`, checked before a recording is written). Packages bring their own manifests (GRDB, swift-crypto). Update it when code starts using another API in Apple's required-reason list.

`InfoPropertyListDeclarationsTests` checks these values and that the manifest is copied into the app.

## Testers

Internal testers (members of the App Store Connect team, up to 100) can install a build once processing finishes. External testers (by email or a public link) need Beta App Review for the first build of a version; the community plugin runtime, which runs JavaScript the person downloads, may draw questions under guideline 2.5.2.
