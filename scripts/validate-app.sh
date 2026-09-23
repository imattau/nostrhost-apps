#!/usr/bin/env bash
# Validate one app's package.toml against the native NostrHost schema and
# produce its plan. Mirrors what security.yml runs per app in CI; this script
# exists so the same check works locally.
#
# Usage:
#   scripts/validate-app.sh <app-dir>
#
# Required environment:
#   NOSTRHOST_YUNOHOST   path to a checkout of imattau/nostrhost-yunohost
#                        (branch nostrhost); defaults to ../nostrhost-yunohost
#   PYTHONPATH           set automatically from NOSTRHOST_YUNOHOST/src if unset
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_DIR="${1:?usage: scripts/validate-app.sh <app-dir>}"
APP_DIR="$(cd "$APP_DIR" && pwd)"
APP_NAME="$(basename "$APP_DIR")"

NOSTRHOST_YUNOHOST="${NOSTRHOST_YUNOHOST:-$REPO_ROOT/../nostrhost-yunohost}"
if [ ! -f "$NOSTRHOST_YUNOHOST/src/nostrhost/package_authoring.py" ]; then
    echo "validate-app.sh: nostrhost-yunohost checkout not found at $NOSTRHOST_YUNOHOST" >&2
    echo "  clone it with: git clone --branch nostrhost https://github.com/imattau/nostrhost-yunohost.git" >&2
    exit 2
fi

export PYTHONPATH="${PYTHONPATH:-$NOSTRHOST_YUNOHOST/src}"
export NPACK_BIN="${NPACK_BIN:-npack}"

echo "==> Validating $APP_NAME"
python3 -m nostrhost.package_authoring validate "$APP_DIR/package.toml" --json

echo "==> Planning $APP_NAME"
python3 -m nostrhost.package_authoring plan "$APP_DIR/package.toml" --json