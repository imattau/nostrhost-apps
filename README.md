# NostrHost app packages (distributed with npack)

A multi-app repository for NostrHost native (`_nh`) packages that are
**distributed as npack `.npk` artifacts** on Nostr/Blossom. Each app lives
in its own subfolder under `apps/` with a `package.toml` (canonical native
manifest), an `app.toml` (upstream build recipe), and a `README.md`.

This is the multi-app, npack-distributed sibling of the per-app
[`nh-package-template`](https://github.com/imattau/nh-package-template)
(the scriptless `_nh` authoring shape) and of
[`nostrhost-npk-example`](https://github.com/imattau/nostrhost/tree/main/packages/nostrhost-npk-example)
(the npack hybrid staged store flow).

## Apps

| App | Version | Upstream |
| --- | --- | --- |
| [write_nostr](apps/write_nostr/) | 0.4.4 | <https://github.com/imattau/write_nostr> |

## How it works

```text
apps/<name>/app.toml + package.toml
        │  build.sh (off-target CI/local build)
        ▼
   deterministic .npk  (payload at host-relative paths, native manifest
                        embedded at .npack/nostrhost/manifest.json)
        │  npack publish  (publisher-signed kind-9900 + NIP-94, Blossom)
        ▼
   Nostr relays / Blossom
        │  nostrhost app install-npk <publisher>/<name> --domain ...
        ▼
   resource engine: payload.sync → directories → web → permissions → health
```

## Conventions

- **Scriptless by construction.** No `scripts/install`, no shell snippet in a
  `[hooks]` entry, no postinst-style trick. Every build happens off the
  install target (this repo's CI or locally); `package.toml`'s resources are
  the only things the host ever applies.
- **`[web].domain` is never hardcoded.** It is an install-time parameter
  (`--domain` on `install-npk`), not part of the package's signed content.
- **Pinned upstreams only.** `app.toml`'s `[upstream].ref` is a tag or commit,
  never a branch.
- **Version is SemVer.** `package.toml` `[app].version` must be a valid SemVer
  string because npack requires it.
- **Platform tags.** Set `[publish].os`/`[publish].arch` to `any` only when
  the payload is genuinely platform-independent; otherwise leave the npack
  default (host).
- **Publisher key is a dedicated key**, supplied at build/publish time
  (`--publisher`, or `NOSTR_PUBLISHER`), never a personal primary identity.

## Per-app files

| File | Purpose |
| --- | --- |
| `package.toml` | Canonical native `_nh` manifest; embedded in the `.npk`. |
| `app.toml` | Build recipe: upstream repo/ref, node version, install/build commands, payload mapping. |
| `README.md` | Build/validate/install instructions for that app. |

## Shared scripts

- `scripts/build-app.sh <app-dir> --output <out.npk> [--publisher <key>]` —
  clones the pinned ref, builds, assembles the host-relative payload, embeds
  the native manifest, runs `npack init` + `npack pack` + `npack hash`.
- `scripts/validate-app.sh <app-dir>` — runs `nostrhost-package validate` +
  `plan` against the native schema.
- `scripts/list-apps.py` / `scripts/check-app-pinned.py` — CI helpers.

See [docs/npack-distribution.md](docs/npack-distribution.md) for the npack
hybrid staged store flow and the native post-install model.

## CI

- `.github/workflows/build.yml` — reusable build core (called with an `app`
  filter); builds each `.npk`, and on a tag- or dispatch-driven release
  attaches it to a GitHub Release and publishes it to Nostr/Blossom with
  `npack publish`. It has no tag trigger of its own and can also be
  dispatched directly to build/publish one app or all of them.
- `.github/workflows/<name>.yml` (one per app, e.g. `nostr_blog.yml`) — thin
  wrapper calling the core with that app's filter, so releases, run history
  and status checks are independent per app. Each wrapper owns its app's
  triggers:
  - tag `apps/<name>/v*` → full release (build, publish, GitHub Release);
  - push to `main` touching `apps/<name>/**`, `scripts/**`, or the build
    chain → build-only validation (publish stays tag/dispatch-gated);
  - manual dispatch → build + publish just that app (optional
    `upstream_ref` override).
  A new app releases only after copying an existing wrapper and adjusting
  its name/paths/filter.
- `.github/workflows/security.yml` — matrix over `apps/*`; validates and plans
  each `package.toml`, re-verifies the pinned artifact hash, and runs the same
  static scans (Gitleaks, Trivy, actionlint, ShellCheck) as the `_nh` template.

Repository configuration mirrors the npack release workflow:

- Variable `NOSTR_PUBLISHER` — the dedicated publisher public key.
- Variables `NOSTR_RELAYS`, `NOSTR_BLOSSOM_SERVERS` — one URL per line.
- Secret `NOSTR_SECRET_KEY` at repository level; the wrappers pass it to the
  core with `secrets: inherit`, and the core's publish job runs under the
  `release` environment.