#!/bin/bash
# Runs the hosted iPad suite on a simulator and stops it at once if the simulator's audio output opens.
#
# The owner's rule is that a test run plays no sound, and that the audio output does not even open: a running audio engine, an
# active audio session or a playing AVPlayer makes coreaudiod hold an "iOSSimulatorAudioDevice ... audio-out" assertion, which
# `pmset -g assertions` lists. This script samples that list every half second while xcodebuild runs, stops the run and fails
# when it sees the assertion, and names the test that was running.
#
# Usage: scripts/run-hosted-suite-silently.sh <simulator udid> <derived data folder> [extra xcodebuild arguments]
#   for example: scripts/run-hosted-suite-silently.sh "$UDID" "$SCRATCH/derived" -only-testing:GraphiteIntegrationTests
set -u
if [ $# -lt 2 ]; then sed -n '2,14p' "$0"; exit 2; fi
udid=$1; derived=$2; shift 2
log=$(mktemp -t hosted-suite).log
trigger=$(mktemp -t audio-open)
rm -f "$trigger"

xcodebuild test -project Graphite.xcodeproj -scheme Graphite -destination "id=$udid" -derivedDataPath "$derived" \
  -skipPackagePluginValidation -skipMacroValidation "$@" > "$log" 2>&1 &
run=$!

# Only this run is stopped (never every xcodebuild on the machine, which other sessions may be running). The assertion
# belongs to this run only when nothing else is testing on a simulator: run it when the machine is otherwise quiet.
(
  while kill -0 "$run" 2>/dev/null; do
    line=$(pmset -g assertions 2>/dev/null | grep -i "audio" | grep -iE "simulator|audio-out" | head -2)
    if [ -n "$line" ]; then
      echo "$line" > "$trigger"
      pkill -P "$run" 2>/dev/null
      kill "$run" 2>/dev/null
      exit 0
    fi
    sleep 0.5
  done
) &
watcher=$!

wait "$run"
status=$?
kill "$watcher" 2>/dev/null

if [ -s "$trigger" ]; then
  echo "AUDIO OUTPUT OPENED while the hosted suite ran:" >&2
  cat "$trigger" >&2
  echo "The test that was running:" >&2
  grep -E "Test Case .* started" "$log" | tail -1 >&2
  exit 1
fi
tail -n 5 "$log"
exit $status
