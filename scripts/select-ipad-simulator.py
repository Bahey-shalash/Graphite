#!/usr/bin/env python3
"""Print the identifier (UDID) of an available iPad simulator, for the `hosted-ipad` job of .github/workflows/ci.yml.

Reads `xcrun simctl list devices available --json`, prefers the newest iOS runtime and, inside it, the model the hosted
suite is written for, an 11-inch iPad Pro (the owner's iPad), then another iPad Pro, an 11-inch iPad Air, any other iPad
and the iPad mini last. The tests measure a regular-width window that has room for the tab bar's tools; the mini's 744-point
window has not, so choosing it (as "iPad mini (A17 Pro)" contains "Pro") fails them. Exits with status 1 and a message when no iPad simulator exists, so the job
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


def model_preference(device):
    """Sort key: smaller is preferred. Newer chips first inside a model, by their position in the name."""
    name = device["name"]
    if name.startswith("iPad Pro 11-inch"):
        rank = 0
    elif name.startswith("iPad Pro"):
        rank = 1
    elif name.startswith("iPad Air 11-inch"):
        rank = 2
    elif "mini" in name:
        rank = 4
    else:
        rank = 3
    # M5 before M4: the highest number in the name, negated.
    chip_numbers = [int(number) for number in re.findall(r"\(M(\d+)\)", name)]
    return (rank, -max(chip_numbers, default=0), name)


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
        print(min(ipads, key=model_preference)["udid"])
        return 0
    print("no available iPad simulator; install an iOS simulator runtime and create an iPad device", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
