#!/bin/bash
# Archives the app in Release and uploads it to App Store Connect, where it appears in TestFlight after processing.
# The iOS app by default; --macos archives the native Mac app instead, which TestFlight on a Mac installs.
#
# The checkout sits in iCloud's Desktop, where codesign fails, so the archive and its derived data go to a folder outside it.
# Every upload needs a build number higher than the last one; this script uses the date and time (for example 20261020.1530),
# so nobody has to raise CURRENT_PROJECT_VERSION by hand. The version people see stays MARKETING_VERSION in the project.
# Xcode must be signed in to the Apple account of team JDP856P5D5 (Xcode > Settings > Accounts).
#
# After archiving it checks the app against scripts/app-size-budget.json and stops before the upload if it grew.
#
# Usage: scripts/archive-for-testflight.sh <build folder outside iCloud> [--macos] [--archive-only] [--allow-size-growth]
#   for example: scripts/archive-for-testflight.sh /tmp/graphite-testflight --macos
set -euo pipefail
if [ $# -lt 1 ]; then sed -n '2,13p' "$0"; exit 2; fi
build_folder=$1
shift
platform=iOS
archive_only=no
allow_size_growth=no
for option in "$@"; do
  case "$option" in
    --macos) platform=macOS ;;
    --archive-only) archive_only=yes ;;
    --allow-size-growth) allow_size_growth=yes ;;
    *) echo "Unknown option $option" >&2; sed -n '2,13p' "$0"; exit 2 ;;
  esac
done
repository_root=$(cd "$(dirname "$0")/.." && pwd)
build_number=$(date +%Y%m%d.%H%M)
archive_path="$build_folder/Graphite-$platform-$build_number.xcarchive"

if ps -axo comm | grep -qE "/(swift-build|swift-test|xcodebuild)$"; then
  echo "Another build or test run is in progress; run this when it has finished." >&2
  exit 1
fi

xcodebuild archive -project "$repository_root/Graphite.xcodeproj" -scheme Graphite -configuration Release \
  -destination "generic/platform=$platform" -archivePath "$archive_path" -derivedDataPath "$build_folder/derived" \
  -allowProvisioningUpdates -skipPackagePluginValidation -skipMacroValidation \
  CURRENT_PROJECT_VERSION="$build_number"

# Graphite stays a small core: a build that grew past its budget is not uploaded by accident.
if ! python3 "$repository_root/scripts/app-size-budget.py" "$archive_path"; then
  if [ "$allow_size_growth" = yes ] || [ "$archive_only" = yes ]; then
    echo "The app is over its size budget; continuing because of --allow-size-growth or --archive-only."
  else
    echo "Stopped before the upload: the app grew past scripts/app-size-budget.json (see above)." >&2
    exit 1
  fi
fi

if [ "$archive_only" = yes ]; then
  echo "Archived $platform build $build_number at $archive_path (not uploaded)."
  exit 0
fi

xcodebuild -exportArchive -archivePath "$archive_path" -exportPath "$build_folder/export-$platform-$build_number" \
  -exportOptionsPlist "$repository_root/App/ExportOptions.plist" -allowProvisioningUpdates

echo "Uploaded $platform build $build_number. It appears in App Store Connect > TestFlight once Apple has processed it."
