#!/usr/bin/env python3
"""Print the identifier (UDID) of an available iPad simulator, for the `hosted-ipad` job of .github/workflows/ci.yml.

Reads `xcrun simctl list devices available --json`, prefers the newest iOS runtime and, inside it, an "iPad Pro" model with
the largest screen name, then any iPad. Exits with status 1 and a message when no iPad simulator exists, so the job
fails with a clear reason rather than with an xcodebuild destination error.

Usage:
  python3 scripts/select-ipad-simulator.py            prints the UDID
"""
import json
import re
import subprocess
import sys


def runtime_sort_key(runtime_identifier):
    """Sort key from `com.apple.CoreSimulator.SimRuntime.iOS-27-0` so that iOS 27.0 sorts after iOS 18.4."""
    match = re.search(r"iOS-(\d+)-(\d+)", runtime_identifier)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)


def main():
    listing = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                             capture_output=True, text=True, check=True).stdout
    devices_by_runtime = json.loads(listing)["devices"]
    for runtime_identifier in sorted(devices_by_runtime, key=runtime_sort_key, reverse=True):
        if "iOS" not in runtime_identifier:
            continue
        ipads = [device for device in devices_by_runtime[runtime_identifier]
                 if "iPad" in device["name"] and device.get("isAvailable", True)]
        if not ipads:
            continue
        pro_models = sorted((device for device in ipads if "Pro" in device["name"]), key=lambda device: device["name"], reverse=True)
        print((pro_models or ipads)[0]["udid"])
        return 0
    print("no available iPad simulator; install an iOS simulator runtime and create an iPad device", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
