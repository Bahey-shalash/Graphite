#!/bin/bash
# Archives the iOS app in Release and uploads it to App Store Connect, where it appears in TestFlight after processing.
#
# The checkout sits in iCloud's Desktop, where codesign fails, so the archive and its derived data go to a folder outside it.
# Every upload needs a build number higher than the last one; this script uses the date and time (for example 20261020.1530),
# so nobody has to raise CURRENT_PROJECT_VERSION by hand. The version people see stays MARKETING_VERSION in the project.
# Xcode must be signed in to the Apple account of team JDP856P5D5 (Xcode > Settings > Accounts).
#
# Usage: scripts/archive-for-testflight.sh <build folder outside iCloud> [--archive-only]
#   for example: scripts/archive-for-testflight.sh /tmp/graphite-testflight
set -euo pipefail
if [ $# -lt 1 ]; then sed -n '2,11p' "$0"; exit 2; fi
build_folder=$1
archive_only=${2:-}
repository_root=$(cd "$(dirname "$0")/.." && pwd)
build_number=$(date +%Y%m%d.%H%M)
archive_path="$build_folder/Graphite-$build_number.xcarchive"

if ps -axo comm | grep -qE "/(swift-build|swift-test|xcodebuild)$"; then
  echo "Another build or test run is in progress; run this when it has finished." >&2
  exit 1
fi

xcodebuild archive -project "$repository_root/Graphite.xcodeproj" -scheme Graphite -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$archive_path" -derivedDataPath "$build_folder/derived" \
  -allowProvisioningUpdates -skipPackagePluginValidation -skipMacroValidation \
  CURRENT_PROJECT_VERSION="$build_number"

if [ "$archive_only" = "--archive-only" ]; then
  echo "Archived build $build_number at $archive_path (not uploaded)."
  exit 0
fi

xcodebuild -exportArchive -archivePath "$archive_path" -exportPath "$build_folder/export-$build_number" \
  -exportOptionsPlist "$repository_root/App/ExportOptions.plist" -allowProvisioningUpdates

echo "Uploaded build $build_number. It appears in App Store Connect > TestFlight once Apple has processed it."
