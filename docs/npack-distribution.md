# npack distribution and the native post-install model

This repo distributes NostrHost native (`_nh`) packages as npack `.npk`
artifacts. Two adjacent codebases define that flow; this file records what
was verified against them and the platform's post-install model.

## The npack integration (hybrid staged store)

The relevant code lives in `imattau/nostrhost-yunohost` (branch `nostrhost`):

- `src/nostrhost/npk.py` — `resolve()` (runs `npack resolve` and requires a
  valid signature, non-revoked release, and a trusted publisher), `stage()`
  (runs `npack install <coordinate> --store <store>`), and reads the
  canonical native manifest embedded at `.npack/nostrhost/manifest.json`.
- `package_authoring.py build-npk` — validates `package.toml`, runs
  `npack init` + `npack pack` + `npack hash`, and embeds the native manifest
  under `.npack/nostrhost/` in the same compact `sort_keys` JSON form.
- `package_engine.py package_plan_envelope(..., npack=...)` — binds the
  resolved publisher/name/version/`artifact_sha256`/`payload_root` into the
  approved plan and appends a single `payload.sync` operation.
- `native_providers.py PayloadSyncProvider` — copies the staged payload
  (skipping the `.npack` metadata directory) into the host root, marker-keyed
  by artifact SHA-256 so reconcile converges and removal reverses the copy.
- `cli.py install-npk` and the `/package/npk/install/plan|apply` API routes
  expose the same flow.

`scripts/build-app.sh` in this repo replicates `build-npk` directly with the
`npack` binary (clone pinned ref → build → assemble host-relative payload →
`npack init` → embed native manifest → `npack pack` → `npack hash`), so the
build path has no Python dependency; `scripts/validate-app.sh` still uses the
official `nostrhost.package_authoring` CLI for schema validation.

## The post-install model (why there are no install scripts)

Native packages are scriptless: the resource engine plans typed operations
from `package.toml` and never executes arbitrary commands on the install
target. Two providers make this explicit:

- `RuntimeProvider` only verifies a runtime is present; it does not install
  or run anything.
- `HookProvider` only registers a restricted `python: module:function`
  reference "without executing them".

Post-install configuration is handled by the `[settings]` resource: commit
`905e9256` ("native: post-install config panel for package.toml [settings]")
added `NativeSettingsProvider` + `nostrhost.native_config`, which generate a
YunoHost-compatible `config_panel.toml` + `scripts/config` from `[settings]`
fields so webadmin / `app.config.read|set` operate on the same typed values
the engine persists.

npack's own install-input descriptors (`docs/package-setup.md` in the npack
repo — signed `install-input` tags, `GetPackage` discovery, daemon
`Install.install_values` validation) are the same idea one layer lower: typed
values submitted at install time, never part of the signed release event.
NostrHost's `[settings]` resource is the platform-side consumer of that
contract; the workspace npack HEAD (ahead of the `forks/npack` pin at
`cf82936`/v0.4.0) already carries the descriptor implementation.

## Serving model for write_nostr

write_nostr is a static SvelteKit SPA. It is served straight from its build
output by Caddy `file_server` (`[web].file_root`), the same shape
`nh-package-template` uses — no service resource, no install-time build.

One platform note: the native `[web]` `file_root` route now applies the same
SPA `try_files` fallback the portal uses (`_spa_route_handle` /
`_spa_file_server_routes` in `caddy_admin.py`), so client-side routes fall
back to `index.html` by default (`[web].spa_fallback`, default true for
`file_root` apps). Set `spa_fallback = false` for a genuinely static site
that wants real 404s.

Another platform note (unchanged): `payload.sync` runs last in the plan (it
depends on the manifest operation), so a health check that runs at apply
time sees the payload in place — ordering is the platform's concern, not the
package's.

## Versioning and trust

- `package.toml` `[app].version` must be SemVer (npack rejects anything
  else); `build-npk` enforces this.
- The publisher key is a dedicated key supplied at build/publish time
  (`--publisher` / `NOSTR_PUBLISHER`), never embedded in the manifest.
- `[web].domain` is never in `package.toml`; it is supplied at install time
  (`nostrhost app install-npk ... --domain ...`).