#!/usr/bin/env python3
"""Report what an archived Graphite app is made of, and fail when it grew past its budget.

Graphite is meant to stay a small core: extras are downloaded add-ons, not part of the app
(Docs/Architecture.md, Add-ons). This script measures an archived app (an .xcarchive or the
.app inside it), prints its main parts, and compares each with scripts/app-size-budget.json.
A part more than 1 % over its budget fails the check, so growth is a decision rather than an
accident. `scripts/archive-for-testflight.sh` runs it after archiving and stops before the
upload when it fails, unless it is given --allow-size-growth.

Usage:
  python3 scripts/app-size-budget.py <Graphite.xcarchive or Graphite.app>
  python3 scripts/app-size-budget.py <archive> --record   # make the measured sizes the new budget
"""
import argparse
import collections
import json
import os
import plistlib
import subprocess
import sys

BUDGET_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "app-size-budget.json")
TOLERANCE = 0.01


def folder_size(path):
    total = 0
    for directory, _, names in os.walk(path):
        for name in names:
            file_path = os.path.join(directory, name)
            if not os.path.islink(file_path):
                total += os.path.getsize(file_path)
    return total


def find_app(path):
    if path.endswith(".app"):
        return path
    applications = os.path.join(path, "Products", "Applications")
    for name in sorted(os.listdir(applications)):
        if name.endswith(".app"):
            return os.path.join(applications, name)
    sys.exit(f"No .app in {applications}")


def measure(app):
    """The parts of the app: the whole bundle, the main binary, the asset catalog and each resource bundle."""
    is_mac = os.path.isdir(os.path.join(app, "Contents"))
    contents = os.path.join(app, "Contents") if is_mac else app
    resources = os.path.join(contents, "Resources") if is_mac else app
    info = plistlib.load(open(os.path.join(contents, "Info.plist"), "rb"))
    binary = os.path.join(contents, "MacOS", info["CFBundleExecutable"]) if is_mac else os.path.join(app, info["CFBundleExecutable"])
    asset_catalog = os.path.join(resources, "Assets.car")
    parts = {
        "app": folder_size(app),
        "binary": os.path.getsize(binary),
        "assetCatalog": os.path.getsize(asset_catalog) if os.path.exists(asset_catalog) else 0,
    }
    bundles = {name: folder_size(os.path.join(resources, name)) for name in sorted(os.listdir(resources)) if name.endswith(".bundle")}
    return ("macOS" if is_mac else "iOS"), parts, bundles, asset_catalog


def asset_catalog_groups(asset_catalog):
    """The asset catalog's renditions grouped by asset name, largest first."""
    if not os.path.exists(asset_catalog):
        return []
    result = subprocess.run(["xcrun", "assetutil", "--info", asset_catalog], capture_output=True, text=True)
    if result.returncode != 0:
        return []
    sizes = collections.Counter()
    for entry in json.loads(result.stdout):
        name = str(entry.get("Name", ""))
        if name:
            sizes[name.split("/")[0]] += entry.get("SizeOnDisk", 0)
    return sizes.most_common(8)


def megabytes(byte_count):
    return f"{byte_count / 1_000_000:6.1f} MB"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("path")
    parser.add_argument("--record", action="store_true", help="write the measured sizes as the new budget")
    arguments = parser.parse_args()

    platform, parts, bundles, asset_catalog = measure(find_app(arguments.path))
    print(f"{platform} app")
    for name, byte_count in parts.items():
        print(f"  {name:<14}{megabytes(byte_count)}")
    for name, byte_count in asset_catalog_groups(asset_catalog):
        print(f"    asset {name:<28}{megabytes(byte_count)}")
    for name, byte_count in sorted(bundles.items(), key=lambda item: -item[1])[:6]:
        print(f"    bundle {name:<27}{megabytes(byte_count)}")

    budgets = json.load(open(BUDGET_PATH)) if os.path.exists(BUDGET_PATH) else {}
    if arguments.record:
        budgets[platform] = parts
        with open(BUDGET_PATH, "w") as budget_file:
            json.dump(budgets, budget_file, indent=2, sort_keys=True)
            budget_file.write("\n")
        print(f"Recorded the {platform} budget in {os.path.relpath(BUDGET_PATH)}.")
        return 0

    budget = budgets.get(platform)
    if budget is None:
        print(f"No {platform} budget yet: run with --record to make these sizes the budget.")
        return 1
    over = [name for name, byte_count in parts.items() if byte_count > budget.get(name, 0) * (1 + TOLERANCE)]
    for name in over:
        print(f"OVER BUDGET  {name}: {megabytes(parts[name])} against {megabytes(budget[name])}")
    if over:
        print("Move the new resources into an add-on pack, or, if the growth is wanted, record a new budget with --record.")
        return 1
    print(f"Within the {platform} budget.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
