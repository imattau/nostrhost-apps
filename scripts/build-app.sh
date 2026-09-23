#!/usr/bin/env bash
# Build one app in this repo into a deterministic .npk.
#
# Reads <app-dir>/app.toml (upstream + build recipe) and <app-dir>/package.toml
# (the canonical native manifest), builds the pinned upstream ref, assembles
# the payload at host-relative paths, embeds the native manifest at
# .npack/nostrhost/manifest.json, and runs `npack init` + `npack pack` +
# `npack hash` exactly like `nostrhost-package build-npk` does.
#
# This runs ONLY off the install target (locally or in CI). Native NostrHost
# packages never execute a build on the host they install to.
#
# Usage:
#   scripts/build-app.sh <app-dir> --output <out.npk> [--publisher <npub|hex>]
#
# Required environment:
#   NPACK_BIN   path to the npack binary (default: npack on PATH)
#   PUBLISHER   publisher npub or 64-character hex public key
#               (fallback: NOSTR_PUBLISHER env)
#
# Outputs <out>.sha256 and prints the artifact path + sha256 for the caller.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_DIR="${1:?usage: scripts/build-app.sh <app-dir> --output <out.npk> [--publisher <npub|hex>] [--upstream-ref <tag|commit>]}"
shift
OUTPUT=""
PUBLISHER=""
UPSTREAM_REF_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT="${2:?--output requires a path}"
            shift 2
            ;;
        --publisher)
            PUBLISHER="${2:?--publisher requires an npub or hex key}"
            shift 2
            ;;
        --upstream-ref)
            UPSTREAM_REF_OVERRIDE="${2:?--upstream-ref requires a tag or commit}"
            shift 2
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 2
            ;;
    esac
done

PUBLISHER="${PUBLISHER:-${NOSTR_PUBLISHER:-}}"
if [ -z "$PUBLISHER" ]; then
    echo "build-app.sh: --publisher (or NOSTR_PUBLISHER) is required" >&2
    exit 2
fi
if [[ ! "$PUBLISHER" =~ ^npub1[a-z0-9]+$ ]] && [[ ! "$PUBLISHER" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "build-app.sh: publisher must be an npub or 64-character hex public key" >&2
    exit 2
fi

NPACK_BIN="${NPACK_BIN:-npack}"
if ! command -v "$NPACK_BIN" >/dev/null 2>&1; then
    echo "build-app.sh: npack binary not found (set NPACK_BIN)" >&2
    exit 2
fi

APP_DIR="$(cd "$APP_DIR" && pwd)"
APP_NAME="$(basename "$APP_DIR")"
if [ -z "$OUTPUT" ]; then
    OUTPUT="$REPO_ROOT/$APP_NAME.npk"
fi
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"

echo "==> Reading app metadata for $APP_NAME"
INFO="$(python3 "$SCRIPT_DIR/app-info.py" "$APP_DIR")"
ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$INFO")"
VERSION="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])' <<<"$INFO")"
UPSTREAM_REPO="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["upstream"]["repo"])' <<<"$INFO")"
UPSTREAM_REF="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["upstream"]["ref"])' <<<"$INFO")"
NODE_VERSION="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["build"]["node"])' <<<"$INFO")"
INSTALL_ARGS="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["build"]["install"])' <<<"$INFO")"
BUILD_ARGS="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["build"]["build"])' <<<"$INFO")"
OUTPUT_DIR="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["build"]["output_dir"])' <<<"$INFO")"
OS_NAME="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("publish",{}).get("os","any"))' <<<"$INFO")"
ARCH="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("publish",{}).get("arch","any"))' <<<"$INFO")"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> Cloning ${UPSTREAM_REPO}@${UPSTREAM_REF_OVERRIDE:-$UPSTREAM_REF}"
UPSTREAM_REF="${UPSTREAM_REF_OVERRIDE:-$UPSTREAM_REF}"
# UPSTREAM_REF may be a tag or a bare commit hash. `--branch` only accepts a
# ref name, so try the fast path first and fall back to a full clone.
if ! git clone --quiet --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$workdir/src" 2>/dev/null; then
    git clone --quiet "$UPSTREAM_REPO" "$workdir/src"
    git -C "$workdir/src" checkout --quiet "$UPSTREAM_REF"
fi

pushd "$workdir/src" >/dev/null

echo "==> Installing dependencies (npm $INSTALL_ARGS)"
# shellcheck disable=SC2086
npm $INSTALL_ARGS

echo "==> Building (npm $BUILD_ARGS)"
# shellcheck disable=SC2086
npm $BUILD_ARGS

if [ ! -d "$OUTPUT_DIR" ] || [ -z "$(ls -A "$OUTPUT_DIR")" ]; then
    echo "build-app.sh: build did not produce non-empty output at $OUTPUT_DIR" >&2
    exit 1
fi

popd >/dev/null

echo "==> Assembling payload at host-relative paths"
# The build output's *contents* are copied to var/www/<id>/ inside the .npk
# (index.html lands at /var/www/<id>/index.html), matching package.toml's
# [web].file_root and [directories.install].path.
PAYLOAD_ROOT="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["payload"]["root"])' <<<"$INFO")"
PAYLOAD_DIR="$workdir/payload/$PAYLOAD_ROOT"
mkdir -p "$PAYLOAD_DIR"
cp -a "$workdir/src/$OUTPUT_DIR/." "$PAYLOAD_DIR/"

echo "==> Building .npk via npack (init + pack)"
# npack init writes .npack/manifest.json and must run before the native
# manifest is embedded (build-npk embeds it into the same payload root).
"$NPACK_BIN" init "$workdir/payload" \
    --name "$ID" \
    --version "$VERSION" \
    --publisher "$PUBLISHER" \
    --os "$OS_NAME" \
    --arch "$ARCH" \
    >/dev/null

# Embed the canonical native manifest at .npack/nostrhost/manifest.json, in
# the same compact sort-keys form nostrhost's _canonical_json() uses, so a
# later install can reconstruct the plan envelope from the artifact alone.
mkdir -p "$workdir/payload/.npack/nostrhost"
python3 - "$APP_DIR/package.toml" "$workdir/payload/.npack/nostrhost/manifest.json" <<'PY'
import json, sys, tomllib

with open(sys.argv[1], "rb") as fh:
    data = tomllib.load(fh)
with open(sys.argv[2], "wb") as fh:
    fh.write(json.dumps(data, sort_keys=True, separators=(",", ":")).encode())
PY

"$NPACK_BIN" pack "$workdir/payload" --output "$OUTPUT"

echo "==> Hashing artifact"
SHA256="$("$NPACK_BIN" hash "$OUTPUT")"
printf '%s' "$SHA256" > "$OUTPUT.sha256"

echo "==> Built $OUTPUT"
echo "    artifact: $(basename "$OUTPUT")"
echo "    sha256:   $SHA256"
echo "    version:  $VERSION"
echo "    os/arch:  ${OS_NAME}/${ARCH}"
{
    echo "artifact=$(basename "$OUTPUT")"
    echo "sha256=$SHA256"
    echo "version=$VERSION"
    echo "id=$ID"
} > "$OUTPUT.env"