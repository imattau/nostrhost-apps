#!/usr/bin/env python3
"""List app dirs that contain a package.toml, as a JSON array.

Usage:
  scripts/list-apps.py [--app <name>] [--tag <apps/<name>/v<version>>]

Used by CI to build the matrix. Filters by an explicit app name or by a
`apps/<name>/v<version>` tag ref; with neither, lists every app.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="")
    parser.add_argument("--tag", default="")
    args = parser.parse_args()

    app_filter = args.app.strip()
    tag_filter = ""
    if args.tag.startswith("refs/tags/apps/"):
        tag_filter = args.tag.removeprefix("refs/tags/apps/").split("/v", 1)[0]

    apps = []
    for entry in sorted((REPO_ROOT / "apps").iterdir()):
        if not (entry / "package.toml").is_file():
            continue
        if app_filter and entry.name != app_filter:
            continue
        if tag_filter and entry.name != tag_filter:
            continue
        apps.append(entry.name)

    json.dump(apps, sys.stdout)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())