#!/usr/bin/env python3
"""Check that one app's upstream ref is pinned and its version is SemVer.

Usage:
  scripts/check-app-pinned.py <app-dir>

Exit 0 when app.toml's [upstream].ref is a tag/commit (not a branch) and
package.toml's [app].version is a valid SemVer string; exit 1 otherwise.
"""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

TAG = re.compile(r"v?\d+\.\d+\.\d+")
COMMIT = re.compile(r"[0-9a-fA-F]{40,64}")
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:[-+].*)?$")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-app-pinned.py <app-dir>", file=sys.stderr)
        return 2
    app_dir = Path(sys.argv[1])
    with (app_dir / "app.toml").open("rb") as fh:
        app = tomllib.load(fh)
    with (app_dir / "package.toml").open("rb") as fh:
        pkg = tomllib.load(fh)
    ref = app["upstream"]["ref"]
    version = pkg["app"]["version"]
    if not (TAG.fullmatch(ref) or COMMIT.fullmatch(ref)):
        print(f"::error::upstream.ref is not a pinned tag/commit: {ref}")
        return 1
    if not SEMVER.fullmatch(version):
        print(f"::error::app.version is not SemVer: {version}")
        return 1
    print(f"ref={ref} version={version} pinned=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())