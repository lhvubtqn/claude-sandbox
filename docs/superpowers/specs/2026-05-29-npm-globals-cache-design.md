# Persistent npm Globals Cache Design

**Date:** 2026-05-29
**Status:** Draft

## Problem

Tools installed inside a container via `npm install -g <pkg>` (e.g. `beads`,
`colbymchenry/codegraph`) are written to `$NVM_DIR/versions/node/<version>/bin/` and
`.../lib/node_modules/`. Neither path is volume-mounted, so any container recreation
discards them. With `claude-sandbox restart` now in routine use and config-drift detection
prompting restarts on reopen, users lose their globally-installed Node tools often enough
to make the install effort feel disposable.

The user wants tools installed once to remain available — both across restarts of a given
project's container and across all of their per-project containers (a shared toolbox).

## Goal

Persist Node global installations across container lifetime and across project containers,
without changing how nvm or node itself are managed.

## Non-Goals

- Caching binaries installed via other package managers (`cargo install`, `pipx`, `pip
  --user`, hand-built tools, `curl | sh`). Out of scope for v1; the user installs npm
  globals only.
- A manifest/reproducibility layer (record installed globals, reinstall on a fresh
  machine). Possible future extension; v1 treats the cache itself as the source of truth.
- A `claude-sandbox install <pkg>` wrapper. Users install with plain `npm install -g`
  inside the container.

## Approach

A new global named volume holds a dedicated **npm prefix** directory that is independent
of nvm's own tree. The image sets `NPM_CONFIG_PREFIX` to that path and puts the prefix's
`bin/` on `PATH`. nvm and the node version baked into the image remain image-managed; only
the layer of user-installed globals lives in the volume.

```
/home/claude/.npm-globals/             ← volume mount (named: npm-globals)
  bin/<binary>                         ← what PATH points at
  lib/node_modules/<pkg>/              ← package contents
```

`npm install -g X` inside the container writes here. The named volume is shared by every
project's container (a global mount), so installing in project A makes the tool available
in project B's container too.

## Why a Separate Prefix Beats Mounting `~/.nvm`

Mounting the entire nvm directory as a volume also "works" but couples two things that
should stay separate:

- **Image-controlled state**: nvm itself, the baked-in default node version, and any
  rebuild that bumps node forward. Should live in the image so a `make install` rebuild
  takes effect.
- **User-controlled state**: globally installed tools the user accumulates.

A separate prefix keeps those layers independent. Concretely:

- Future image rebuilds with a newer node version actually take effect — the volume does
  not shadow nvm's tree.
- `nvm install <newer>` inside a container does not nuke globals, because globals live
  outside nvm's per-version `lib/node_modules`. Bonus over a single all-of-nvm mount.
- A corrupted globals cache can be reset (`docker volume rm npm-globals`) without
  touching node, nvm, or any other persistent state.

## Changes

### `Dockerfile`

Three additions, no removals:

1. Pre-create the prefix directory in the existing `mkdir -p` line (so the empty
   directory exists in the image with correct ownership before any container starts):

   ```dockerfile
   RUN mkdir -p /home/claude/.vscode-server /home/claude/.ssh /home/claude/.npm-globals && \
       chmod 700 /home/claude/.ssh
   ```

   Docker only seeds a named volume from the image when both the source path exists in
   the image **and** the volume is empty; pre-creating with `claude:claude` ownership
   (inherited from the parent `USER claude` directive) gives the volume the right owner on
   first init.

2. Set the npm prefix env var so npm's resolution picks up the dedicated path regardless
   of any `.npmrc` files:

   ```dockerfile
   ENV NPM_CONFIG_PREFIX=/home/claude/.npm-globals
   ```

3. Extend the `PATH` env var to include the prefix's `bin/`. Inserted just before
   `default-node-bin` so user-installed globals are searched in the same band as other
   user tool dirs (`.cargo/bin`, `.local/bin`, etc.):

   ```dockerfile
   ENV PATH="/home/claude/.cargo/bin:/home/claude/.local/share/solana/install/active_release/bin:/home/claude/.avm/bin:/home/claude/.local/bin:/home/claude/.npm-globals/bin:/home/claude/.nvm/default-node-bin:${PATH}"
   ```

### `configurations.yml.template`

Add one entry to the global `volumes:` list (sorted with the other cache volumes):

```yaml
volumes:
  - claude-config:/home/claude/.claude
  - cargo-registry:/home/claude/.cargo/registry
  - cargo-git:/home/claude/.cargo/git
  - rustup-downloads:/home/claude/.rustup/downloads
  - npm-cache:/home/claude/.npm
  - npm-globals:/home/claude/.npm-globals   # new
  - solana-config:/home/claude/.config/solana
  - vscode-server:/home/claude/.vscode-server
  # ...
```

### `README.md`

Two additions:

1. Add a row to the volume map table:

   ```
   | `npm-globals`     | `/home/claude/.npm-globals`           | Globally-installed npm packages (`npm install -g`) |
   ```

2. Add a short one-time upgrade note (somewhere near the volume map or Quick Reference)
   pointing existing users at
   `claude-sandbox global mounts add npm-globals:/home/claude/.npm-globals` — see the
   *Updating existing `configurations.yml`* section below.

No changes to `functions/claude-sandbox.fish`, `completions/claude-sandbox.fish`, or
`entrypoint.sh`. No new subcommand. No `_sandbox_render_config` change (the volume is
declared globally in the template just like the existing caches, so it flows through the
existing snapshot machinery automatically).

## Migration

### Existing users

A user who already has an image built and a container running before this change carries
npm globals (if any) in the old location (`$NVM_DIR/versions/node/<v>/bin/`). The first
time they rebuild the image and recreate containers, those globals will not migrate
automatically. They reinstall once with `npm install -g <pkg>`; subsequent restarts
preserve the install through the new volume.

No migration script. The npm tarball cache (`~/.npm`, already volume-mounted) keeps the
reinstall fast — typically just a re-link, no network.

### Updating existing `configurations.yml`

`_sandbox_config_file` (`functions/claude-sandbox.fish:1`) seeds
`configurations.yml` from the template **only when the file does not exist**. Existing
users therefore will not automatically pick up the new `npm-globals` volume line by virtue
of the template changing — their `configurations.yml` already exists and is untouched.

Two equivalent ways for existing users to apply the new entry:

- `claude-sandbox global mounts add npm-globals:/home/claude/.npm-globals` — the
  supported, in-CLI route.
- Hand-edit `configurations.yml` to add the entry to `global.container.volumes`.

Either way, the next reopen triggers config-drift detection (because the rendered config
gains a new `volume` line that the container's snapshot label lacks). The drift detector
reports `+ volume npm-globals:/home/claude/.npm-globals` and prompts to restart. Accepting
recreates the container with the new volume; subsequent `npm install -g` writes persist.

The README's "Use it" / migration paragraph should call out this one-time step so users
upgrading the repo know to run the `mounts add` command (or edit the file) once. No
auto-migration script — the cost is one command per existing install, and an automatic
template-to-config merger is a much larger scope than this feature warrants.

## Edge Cases

- **Project-local `.npmrc` overriding `prefix`.** Some projects ship an `.npmrc` setting
  `prefix=...`. The `NPM_CONFIG_PREFIX` environment variable takes precedence over any
  file-based `prefix` setting in npm's resolution order, so this remains robust.
- **`npm install -g` without `NPM_CONFIG_PREFIX` taking effect.** Would write to nvm's
  per-version path (the old behavior). Guarded by the env var being set globally in the
  image; verifiable by `npm config get prefix` returning the new path.
- **Permission errors on the volume.** First-init only — handled by the `mkdir -p` step
  creating the directory under `USER claude` so the volume inherits `claude:claude`
  ownership.
- **Node version bump via `nvm install <new>` inside the container.** Globals survive the
  switch because they live outside `$NVM_DIR/versions/node/<v>/lib/node_modules`. The
  symlinks in `npm-globals/bin/` continue to resolve as long as the binaries themselves
  remain executable scripts whose shebang line targets `node` (the typical case for
  npm-shipped CLIs) — and `node` on `PATH` resolves to whatever the current default is.
- **Resetting the cache.** `docker volume rm npm-globals` removes only the globals; nvm,
  node, and other volumes are untouched. Volume is recreated empty on the next container
  start.

## Testing

Manual smoke test (no automated test infra exists for the container itself in this repo).

1. Rebuild the image: `make install`.
2. Open a fresh sandbox in project A: `claude-sandbox`.
3. Verify the prefix is in effect:
   - `npm config get prefix` → `/home/claude/.npm-globals`
   - `echo $PATH` includes `/home/claude/.npm-globals/bin`.
4. `npm install -g cowsay && cowsay hi` → ASCII cow prints, binary at
   `/home/claude/.npm-globals/bin/cowsay`.
5. `claude-sandbox restart <project-A>`; reattach; `cowsay hi` → still works (survives
   restart).
6. From a second project: `claude-sandbox` in project B; `cowsay hi` → works (shared
   across containers).
7. `which cowsay` in both → `/home/claude/.npm-globals/bin/cowsay`.

Failure modes to watch for during the test:

- A baked node version's bundled `npm` writing to its own prefix anyway (would indicate
  the env var was not picked up — check `npm config get prefix`).
- `cowsay` not on `PATH` after restart (would indicate `PATH` ordering bug — check
  `echo $PATH`).
- Permission denied on `npm install -g` (would indicate the volume initialized with
  wrong ownership — `docker volume inspect npm-globals` and the directory's `ls -la`
  inside the container will diagnose).

## Out of Scope (v1)

- Caching `cargo install` binaries (`~/.cargo/bin`). The user does not currently install
  via cargo; if they start, a follow-up adds the same pattern (`cargo-bin` volume at
  `~/.cargo/bin`).
- Caching `pip --user` / `pipx` binaries (`~/.local/bin`). Same shape if needed later.
- A manifest of installed globals for cross-machine reproducibility. Tracked as a possible
  future extension; not part of v1.
- A `claude-sandbox npm-globals reset` (or similar) wrapper around `docker volume rm`.
  Users can run the docker command directly.
