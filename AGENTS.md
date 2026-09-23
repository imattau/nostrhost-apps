# Agent guidance for this repo

This is a multi-app repository of native NostrHost (`_nh`) packages
distributed as npack `.npk` artifacts. It builds on
[`nh-package-template`](https://github.com/imattau/nh-package-template) (the
scriptless `_nh` authoring shape) and the npack hybrid staged store flow
(`build-npk` / `install-npk` in `imattau/nostrhost-yunohost`).

Read this before editing any `package.toml`, `app.toml`, or workflow.

## The one hard rule

**Never add anything that executes a command on the NostrHost install
target.** No `scripts/install`, no shell snippet in a `[hooks]` entry, no
`postinst`-style trick. `package.toml` is validated and applied by a
declarative resource engine; builds happen only off-target, in this repo's
CI or locally. See `docs/security-model.md` in nh-package-template for the
reasoning.

Concretely: `app.toml` pins an upstream ref, `scripts/build-app.sh` builds
it and assembles the payload, and the resulting `.npk` embeds the canonical
`package.toml` at `.npack/nostrhost/manifest.json` for the host to apply via
`payload.sync` + the typed resources. The host never builds anything.

## Authoring loop for a new app

1. Create `apps/<name>/` with `package.toml`, `app.toml`, and `README.md`.
   Keep ids and paths consistent (same app id threaded through
   `[app].id`, `[directories.install].path`, `[web]` `path`/`file_root`,
   `[permissions.main]`, `[health].path`).
2. **Do not add `[web].domain`** — it is an install-time parameter
   (`nostrhost app install-npk <publisher>/<name> --domain …`), not part of
   the package's signed content.
3. Pin `app.toml`'s `[upstream].ref` to a tag or commit, never a branch.
4. Validate before touching CI:

   ```sh
   git clone --branch nostrhost https://github.com/imattau/nostrhost-yunohost .nostrhost-yunohost
   python -m pip install "typer==0.7.0" "click==8.1.7" "pydantic==1.10.14" "PyYAML==6.0.2"
   PYTHONPATH=.nostrhost-yunohost/src python -m nostrhost.package_authoring validate package.toml --json
   PYTHONPATH=.nostrhost-yunohost/src python -m nostrhost.package_authoring plan package.toml --json
   ```

   (`scripts/validate-app.sh` does this for one app dir.)
5. Build and verify the `.npk` locally:

   ```sh
   NPACK_BIN=... scripts/build-app.sh apps/<name> --output /tmp/<name>.npk --publisher <npub-or-hex>
   ```

   Then `npack verify`, `npack manifest`, and a store install
   (`npack install --store /tmp/store --allow-capability …`) to confirm the
   staged payload + embedded manifest.
6. `.github/workflows/build.yml` and `security.yml` are a matrix over
   `apps/*`; a new app subfolder is picked up automatically.

## Behavior notes

- `[publish].os`/`[publish].arch` default to `any`/`any`. Only use that for
  genuinely platform-independent payloads (static web assets). Otherwise
  omit them and let npack record the host platform.
- A manifest's `[app].version` must be valid SemVer (npack rejects
  non-SemVer). Use a plain version like `0.4.4`, or a SemVer-compatible
  suffix.
- Static SPAs are served via `[web].file_root` → Caddy `file_server`. The
  native route currently does **not** add SPA `try_files` fallback, so
  client-side deep links may 404 on refresh; document this per app rather
  than silently adding a service to paper over it. (A `[service]` resource
  that runs a fallback-capable server is a legitimate alternative, but
  decide deliberately and match the platform's current capability.)
- The embedded manifest digest binds the plan to the artifact: never edit
  `package.toml` after building without rebuilding the `.npk`.

## Don't

- Don't invent a SHA-256, a URL, or a version number. If you don't have a
  real build, say so and leave placeholders.
- Don't point `[upstream].ref` at a mutable ref (a branch, a "latest"
  redirect, a moving tag target).
- Don't add `[hooks]` as a way to sneak in imperative behavior.
- Don't hardcode `[web].domain` in `package.toml`.
- Don't commit a `.npk`, a build-output tree, `node_modules`, or a
  `nostrhost-yunohost` checkout into this repo.
- Don't weaken a check in `security.yml` to make a run pass — a failure is a
  real defect.