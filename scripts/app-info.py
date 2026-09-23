#!/usr/bin/env python3
"""Print the build metadata for one app as JSON.

Reads ``<app-dir>/app.toml`` (upstream + build recipe) and
``<app-dir>/package.toml`` (the native manifest, for ``[app] id/version``)
and prints a single JSON object the build script can consume:

    {
      "id": "write_nostr",
      "version": "0.4.4",
      "upstream": {"repo": "...", "ref": "v0.4.4"},
      "build": {"node": "22", "install": "...", "build": "...", "output_dir": "build"},
      "payload": {"build": "var/www/write_nostr/build", ...}
    }

``payload`` maps a source path inside the upstream checkout (key) to a
host-relative destination inside the .npk archive (value). The destination
must stay under the host root the resource engine installs to.
"""

from __future__ import annotations

import json
import sys
import tomllib
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: app-info.py <app-dir>", file=sys.stderr)
        return 2
    app_dir = Path(sys.argv[1]).resolve()
    app_toml = app_dir / "app.toml"
    package_toml = app_dir / "package.toml"
    if not app_toml.is_file():
        print(f"no app.toml in {app_dir}", file=sys.stderr)
        return 2
    if not package_toml.is_file():
        print(f"no package.toml in {app_dir}", file=sys.stderr)
        return 2
    with app_toml.open("rb") as fh:
        app = tomllib.load(fh)
    with package_toml.open("rb") as fh:
        pkg = tomllib.load(fh)

    info = {
        "id": app.get("app", {}).get("id", pkg["app"]["id"]),
        "version": pkg["app"]["version"],
        "upstream": {
            "repo": app["upstream"]["repo"],
            "ref": app["upstream"]["ref"],
        },
        "build": {
            "node": app.get("build", {}).get("node", "22"),
            "install": app.get("build", {}).get("install", "ci --ignore-scripts"),
            "build": app.get("build", {}).get("build", "run build"),
            "output_dir": app.get("build", {}).get("output_dir", "build"),
        },
        "payload": app.get("payload", {}),
        "publish": {
            "os": app.get("publish", {}).get("os", "any"),
            "arch": app.get("publish", {}).get("arch", "any"),
        },
    }
    if not info["payload"]:
        print(f"app.toml has no [payload] mapping in {app_dir}", file=sys.stderr)
        return 2
    json.dump(info, sys.stdout, indent=2, sort_keys=True)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())