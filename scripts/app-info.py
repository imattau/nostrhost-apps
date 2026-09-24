#!/usr/bin/env python3
"""Print the build metadata for one app as JSON.

Reads ``<app-dir>/app.toml`` (upstream + build recipe) and
``<app-dir>/package.toml`` (the native manifest, for ``[app] id/version``)
and prints a single JSON object the build script can consume:

    {
      "id": "write_nostr",
      "version": "0.4.4",
      "upstream": {"repo": "...", "ref": "v0.4.4"},
      "build": {"node": "22", "install": "...", "build": "...",
                "output_dir": "build", "env": {"KEY": "value"}},
      "payload": {"root": "var/www/write_nostr", "include": ["dist", ...]}
    }

``payload`` carries the host-relative destination root (value of ``root``).
When ``include`` lists entries, the build script copies exactly those paths
(from the upstream checkout, by name) into the payload root; when ``include``
is absent, the *contents* of ``build.output_dir`` are copied instead (the
legacy static-app behaviour). ``build.env`` is exported into the npm
install/build steps (e.g. NOSTRBLOG_SITEMAP=0 to skip the sitemap).
"""

from __future__ import annotations

import json
import re
import sys
import tomllib
from pathlib import Path

_ENV_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


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

    build = app.get("build", {})
    env = build.get("env", {})
    if not isinstance(env, dict) or any(
        not isinstance(key, str) or not _ENV_KEY.match(key)
        or not isinstance(value, (str, int, float, bool))
        for key, value in env.items()
    ):
        print(f"app.toml [build.env] must map shell-safe keys to scalar values in {app_dir}", file=sys.stderr)
        return 2
    payload = app.get("payload", {})
    if not payload:
        print(f"app.toml has no [payload] mapping in {app_dir}", file=sys.stderr)
        return 2
    if "root" not in payload:
        print(f"app.toml [payload] is missing root in {app_dir}", file=sys.stderr)
        return 2
    include = payload.get("include", [])
    if not isinstance(include, list) or any(
        not isinstance(entry, str) or not entry or entry.startswith("/")
        or ".." in Path(entry).parts
        for entry in include
    ):
        print(f"app.toml [payload].include must be a list of relative paths in {app_dir}", file=sys.stderr)
        return 2

    info = {
        "id": app.get("app", {}).get("id", pkg["app"]["id"]),
        "version": pkg["app"]["version"],
        "upstream": {
            "repo": app["upstream"]["repo"],
            "ref": app["upstream"]["ref"],
        },
        "build": {
            "node": build.get("node", "22"),
            "install": build.get("install", "ci --ignore-scripts"),
            "build": build.get("build", "run build"),
            "output_dir": build.get("output_dir", "build"),
            "env": env,
        },
        "payload": payload,
        "publish": {
            "os": app.get("publish", {}).get("os", "any"),
            "arch": app.get("publish", {}).get("arch", "any"),
        },
    }
    json.dump(info, sys.stdout, indent=2, sort_keys=True)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())