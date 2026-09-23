# write_nostr

Distraction-free long-form Markdown writing and publishing app for Nostr
(NIP-23), packaged as a native NostrHost (`_nh`) package and distributed as
an npack `.npk` artifact.

Upstream: <https://github.com/imattau/write_nostr>

## What this package does

- Builds the pinned upstream tag (`v0.4.4`) with `npm ci --ignore-scripts &&
  npm run build` — this happens **off the install target**, in this repo's CI
  or locally, never on the NostrHost host (see
  `../docs` / AGENTS.md for the scriptless-package security model).
- Packs the resulting static SPA into a deterministic `.npk` together with
  this `package.toml` embedded at `.npack/nostrhost/manifest.json`.
- At install, the resource engine serves the payload from
  `/var/www/write_nostr` via Caddy (`[web].file_root`), registers the
  permission and health check, and records it for backup/removal.

write_nostr is a static client-side SPA. All data (drafts, relay list,
cached articles, identities) lives in the visitor's browser; this package
keeps no server-side application data, and installs no Nostr relay.

## Build the .npk

```bash
# npack binary (workspace root of imattau/npack, or NPACK_BIN)
cargo build --release --manifest-path ../npack/Cargo.toml
NPACK_BIN="$PWD/../npack/target/release/npack" \
  scripts/build-app.sh apps/write_nostr \
  --output /tmp/write_nostr-0.4.4.npk \
  --publisher <npub-or-hex>
```

Prints the artifact path and SHA-256. The external publish manifest can be
generated from the artifact with `npack manifest`:

```bash
"$NPACK_BIN" manifest /tmp/write_nostr-0.4.4.npk --output /tmp/write_nostr-0.4.4.manifest.json
```

## Validate the manifest

```bash
scripts/validate-app.sh apps/write_nostr
```

Requires a checkout of `imattau/nostrhost-yunohost` (branch `nostrhost`) as
`NOSTRHOST_YUNOHOST` (defaults to `../nostrhost-yunohost`).

## Install on a NostrHost host

The `.npk` is published to Blossom with a publisher-signed kind-9900 release
(see `.github/workflows/build.yml`), then installed through the hybrid staged
store:

```bash
nostrhost app install-npk <publisher>/write_nostr \
  [--relay wss://relay.example] [--store /var/lib/nostrhost/npack-store] \
  [--domain example.com]
```

`[web].domain` is supplied at install time, never hardcoded in the manifest.
Note: the native `[web]` `file_root` route currently serves the static SPA
with plain `file_server` — client-side deep links (e.g. a shared
`/article/…` URL) are a known NostrHost platform gap and may 404 on refresh;
in-app navigation works normally.

## Version bumps

1. Edit `app.toml` `[upstream].ref` to the new pinned tag/commit.
2. Bump `package.toml` `[app].version` to match.
3. Run `.github/workflows/build.yml` (manual) with the new ref, or tag
   `apps/write_nostr/v<version>`.
4. Commit the new `package.toml` version together with the published
   artifact's provenance.