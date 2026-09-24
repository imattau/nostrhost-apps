# nostr_blog

Minimal Nostr blogging platform (SSR Astro site + JSON API), packaged as a
native NostrHost (`_nh`) package and distributed as an npack `.npk`
artifact.

Upstream: <https://github.com/imattau/nostr-blog> (tag `v0.2.0`)

## What this package does

- Builds the pinned upstream tag (`v0.2.0`) with `NOSTRBLOG_SITEMAP=0 npm ci
  --ignore-scripts && NOSTRBLOG_SITEMAP=0 npm run build` — this happens
  **off the install target**, in this repo's CI or locally, never on the
  NostrHost host (see AGENTS.md for the scriptless-package security model).
- Packs `dist/`, `node_modules/` and `package.json` into a deterministic
  `.npk` together with this `package.toml` embedded at
  `.npack/nostrhost/manifest.json`.
- At install, the resource engine syncs the payload to
  `/var/www/nostr_blog`, writes `/var/lib/nostr_blog/config.json` from the
  optional install inputs, starts `node dist/server/entry.mjs` as the
  `nostr_blog` system user behind a public Caddy route
  (`[web].auth = "none"`, ynh parity), and registers the health check and
  Restic backup of the data directory.

Unlike write_nostr (static SPA, Caddy file_server), this is a Node SSR
server: the host must provide **Node 22** before install (the engine's
runtime provider only *verifies* `node --version`, it never installs).
nostr-tools needs the native `WebSocket` global from Node 22.

Upstream changes for NostrHost (pushed as `v0.2.0` on imattau/nostr-blog):
runtime `bootstrap_relays` + `NOSTRBLOG_DATA_DIR` config-dir override,
request-origin site URLs (replacing the build-time `site` constant),
`NOSTRBLOG_SITEMAP=0` build gate, and a fix for the pre-existing
`<script id="nostr-blog-data">` JSON block that was emitted as literal
text (Load More never worked upstream).

## Build the .npk

```bash
# npack binary (workspace root of imattau/npack, or NPACK_BIN)
cargo build --release --manifest-path ../npack/Cargo.toml
NPACK_BIN="$PWD/../npack/target/release/npack" \
  scripts/build-app.sh apps/nostr_blog \
  --output /tmp/nostr_blog-0.2.0.npk \
  --publisher <npub-or-hex>
```

Prints the artifact path and SHA-256. The payload ships `node_modules`
(~200 MB before compression; SSR server chunks resolve bare imports at run
time and the package has no devDependencies to prune). The external
publish manifest can be generated from the artifact with `npack manifest`:

```bash
"$NPACK_BIN" manifest /tmp/nostr_blog-0.2.0.npk \
  --output /tmp/nostr_blog-0.2.0.manifest.json
```

## Validate the manifest

```bash
scripts/validate-app.sh apps/nostr_blog
```

Requires a checkout of `imattau/nostrhost-yunohost` (branch `nostrhost`) as
`NOSTRHOST_YUNOHOST` (defaults to `../nostrhost-yunohost`).

## Install on a NostrHost host

Prerequisite: Node 22 on the host (e.g. official tarball into
`/usr/local`, plus a `/usr/bin/node` symlink so daemons with a minimal
PATH still find it).

The `.npk` is published to Blossom with a publisher-signed kind-9900
release (see `.github/workflows/build.yml`), then installed through the
hybrid staged store:

```bash
nostrhost app install-npk <publisher>/nostr_blog \
  [--relay wss://relay.example] [--store /var/lib/nostrhost/npack-store] \
  --domain example.com \
  [--set npub=npub1...] \
  [--set bootstrap_relays=wss://relay1.example,wss://relay2.example]
```

`[web].domain` is supplied at install time, never hardcoded in the
manifest. `npub` and `bootstrap_relays` are optional install inputs bound
into `/var/lib/nostr_blog/config.json`; when omitted the app falls back to
its built-in relay defaults.

Install-time state lives in `/var/lib/npack`-style engine paths plus this
app's `/var/lib/nostr_blog` (config.json, posts) — both registered for
backup. The site is public: Caddy serves the route without forward_auth
(`[web].auth = "none"`); the `/api/setup` bearer token gates writes inside
the app itself.

Known limitation: `app remove` currently stops the service and deletes the
synced payload + config, but a data directory that contains
app-written posts fails the engine's `directory.remove` (rmdir-only) —
remove any site data first, or wait for a purge-capable removal.

## Version bumps

1. Edit `app.toml` `[upstream].ref` to the new pinned tag/commit.
2. Bump `package.toml` `[app].version` to match.
3. Run `.github/workflows/build.yml` (manual) with the new ref, or tag
   `apps/nostr_blog/v<version>`.
4. Commit the new `package.toml` version together with the published
   artifact's provenance.
