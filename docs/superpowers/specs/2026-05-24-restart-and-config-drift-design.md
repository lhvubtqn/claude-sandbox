# `claude-sandbox restart` + Config-Drift Detection Design

**Date:** 2026-05-24
**Status:** Draft

## Problem

Container mounts and other `docker run` options are fixed at creation time. Once a
container exists, editing `configurations.yml` (e.g. `claude-sandbox mounts add`) has no
effect — the next `claude-sandbox` reattaches the existing container via `docker start`,
which reuses the original arg set. The user has no way to:

1. Apply changed config to an existing container without manually running
   `claude-sandbox stop --rm` then `claude-sandbox`.
2. Know that a running container is out of sync with the current config, or see *what*
   drifted.

## Goal

- Add `claude-sandbox restart <target>` that recreates a container with the current
  config and reattaches VS Code — the supported way to apply config changes.
- On reopen, detect config drift, show *what changed*, and offer to restart.

Both features share one substrate: a **config snapshot** stored on the container at
creation, compared against the freshly-rendered config later.

---

## Config Snapshot (shared substrate)

### `_sandbox_render_config <project_path>`

New helper that emits a canonical, deterministic, one-entry-per-line text rendering of the
**entire effective** config for a project — every option that `_sandbox_docker_run`
applies from `configurations.yml`. Categories, each sorted within itself, in a fixed
category order:

```
image	<image>
volume	<spec>
volume	<spec>
security_opt	<opt>
extra_host	<host>
git_auth_type	<type>
git_auth_path	<path>
git_prefer_ssh	<true|false>
git_identity_name	<name>
git_identity_email	<email>
```

- `image`: `(.projects[$p].container.image // .global.container.image // "claude-sandbox")`.
- `volume`: union of `(.global.container.volumes // []) + (.projects[$p].container.volumes
  // [])`.
- `security_opt`, `extra_host`: same global-then-project union as `_sandbox_docker_run`.
- `git_auth_*`: the resolved git-auth type, creds path, prefer-ssh flag, and identity.
  Each line is emitted **only when `_sandbox_docker_run` would apply the corresponding
  arg** — `git_auth_path` only for `ssh`/`pat`, `git_prefer_ssh` only for `ssh` when true,
  `git_identity_name`/`git_identity_email` only when set. The snapshot thus mirrors the
  actual run args, with no spurious empty-valued lines.
- Specs/paths are stored **raw** (e.g. `~/data:/data`, `${WORKDIR}/x:/x`). Variable
  expansion is deterministic (`WORKDIR` = config-file dir, `HOME` fixed), so raw-vs-raw
  comparison is valid and reads better in a diff.
- Sorted within each category so reordering entries in YAML is not treated as drift.
- The project workspace bind mount is **derived** from the path (constant for a given
  container) and is excluded; the git-auth creds *mount* is captured via `git_auth_path`
  rather than as a `volume` line.

This one function is the single definition of "what counts as config." Adding or removing
a tracked option means editing only this function — it flows into both the stored snapshot
and the diff with no other code changes.

### Snapshot label

`_sandbox_docker_run` stores the rendered snapshot as a base64-encoded container label:

```
--label claude-sandbox.config-snapshot=<base64 of _sandbox_render_config output>
```

Rationale for base64: the snapshot is multi-line; base64 keeps it a single safe label
value. (Matches the existing pattern of encoding payloads, cf. the `xxd` VS Code URI.)

---

## Drift Detection

### `_sandbox_config_diff <project_path> <container_name>`

- Reads the container's `claude-sandbox.config-snapshot` label and base64-decodes it →
  the **before** snapshot. A **missing label decodes to the empty string** (see Existing
  Containers below) — there is no special-case branch.
- Computes `_sandbox_render_config <project_path>` → the **after** snapshot.
- Line-diffs before vs after and prints human-readable changes to stdout, one per
  changed entry across any category:
  - `+ <category> <value>` — present now, absent at creation (added)
  - `- <category> <value>` — present at creation, absent now (removed)

  A changed single-valued field (e.g. `image`) appears as a `-` of the old value and a
  `+` of the new (`- image foo:1`, `+ image foo:2`).
- **Return code:** non-zero when there is any difference (drift), zero when identical.

### Existing containers (pre-feature)

Containers created before this feature carry no `config-snapshot` label. Per design
intent, **no special handling** is added for them:

- The missing label is treated as an empty baseline. The diff therefore renders every
  current config entry as an addition (`+ image …`, `+ volume …`, `+ git_auth_type …`, …),
  drift is reported, and the reopen flow prompts the user to restart (see below).
- Because the "after" snapshot always contains at least `image` and `git_auth_type`, a
  labelless legacy container *always* registers as drifted and is therefore prompted to
  restart on its next reopen — the intended "existing containers get prompted to restart"
  behavior, achieved with no special-case code.
- On restart, the container is recreated by `_sandbox_docker_run`, which writes the
  snapshot label. Subsequent reopens diff accurately against real config changes only.

---

## Reopen UX (`_sandbox_launch`)

`_sandbox_launch` is the shared entry point for the bare `claude-sandbox`, `open`, and any
other reopen. The drift check runs whenever an **existing** container would be reused —
states `running`, `exited`, `created`, `paused` — *before* the `docker start`/attach.

When `_sandbox_config_diff` reports drift, the **drift policy** decides what to do. There
is currently a single policy applied to all drift: **restart, defaulting to yes.** The
diff is shown, then the user is prompted with restart as the default:

```
Configuration for <project> has changed since this container was created:
  + volume ~/data:/data
  - image  claude-sandbox:1
  + image  claude-sandbox:2
Restart the container to apply these changes? [Y/n]
```

- **Default Yes** (Enter) → recreate (`stop` → `rm` → `_sandbox_docker_run`) → attach.
  Same path as the `restart` command. Showing the diff first means the user sees what will
  change (and that a running Claude session will end) before confirming.
- **No** (`n`) → attach to the existing container as-is, leaving it untouched.

No drift → current behavior unchanged (start/attach silently).

### Drift policy (extensibility)

Today the policy is uniform: any drift → prompt with default restart. The design
anticipates **per-category policies** later — e.g. a `volume` change might prompt-restart
while some other category might only warn, or auto-restart silently. This is a future
refinement; v1 keeps one policy for all categories. Because the diff is already
category-tagged (`+ volume …`, `- image …`), routing categories to different policies
later is a localized change in the reopen handler, not in the snapshot/diff machinery.

---

## `restart` Subcommand

```
claude-sandbox restart <target>
```

### Target resolution

Identical to `open` (`functions/claude-sandbox.fish:685`):

1. **Container-name match** — `docker inspect --format '{{ index .Config.Labels
   "claude-sandbox.project" }}' <target>`; if it yields a non-empty path, use it.
2. **Path fallback** — `realpath <target>`; error out non-zero if it does not resolve.

A missing `<target>` or `--help` prints usage.

### Behavior — recreate + attach, always

`restart` is the explicit "apply current config now" action. When a container exists it
recreates without gating on drift; when none exists it asks first rather than silently
creating one:

1. Compute `container_name` from the resolved path.
2. Run the shared preflight (Docker-running check, git-auth resolution + creds
   verification) — the same checks `_sandbox_launch` performs today.
3. **If a container exists for the path:** print the drift diff (when a snapshot label is
   present, for transparency about what is being applied), then `docker stop` → `docker
   rm`.
4. **If no container exists for the path:** prompt
   `No sandbox exists for <path>. Create one? [y/N]`. **Default No** → abort
   (non-zero), nothing created. Yes → continue.
5. `_sandbox_docker_run` to (re)create with current config (writes a fresh snapshot label).
6. Attach VS Code.

The "no container" prompt only applies to **path** targets — a container-name target by
definition already exists, so it always recreates. A path that does not resolve on disk
(`realpath` fails) is still a hard error, distinct from the create prompt: we never offer
to create a sandbox for a directory that does not exist.

### Refactor to avoid duplication

To keep `restart`, the drift "Yes" branch, and `_sandbox_launch` consistent, extract two
small helpers from the tail of `_sandbox_launch`:

- `_sandbox_attach <container_name> <project_name>` — the `xxd` encode + `code
  --folder-uri` block (currently `functions/claude-sandbox.fish:441-443`).
- `_sandbox_recreate <container_name> <project_path> <project_name>` — `stop` (if running)
  → `rm` (if exists) → `_sandbox_docker_run` → `_sandbox_attach`.

The shared preflight (Docker check + git-auth resolve/verify, currently
`_sandbox_launch:384-405`) is also reused by `restart`; it may be extracted into a helper
or `restart` may call into a thin shared path. Exact factoring is left to the
implementation plan; the requirement is that `restart` and `_sandbox_launch` share this
logic rather than duplicating it. No behavioral change to the bare command or `open`.

---

## Completions & Help

### `completions/claude-sandbox.fish`

- Add `restart` to the `$subcommands` list.
- Add a top-level completion entry for `restart`.
- Reuse the existing `__claude_sandbox_open_targets` helper for `restart`'s `<target>`
  (same path/name candidates as `open`), with `-f` to suppress file completion.
- Add the `--help` completion under `restart`.

### Help text

Top-level `claude-sandbox --help` gains:

```
  restart <target>                  Recreate a sandbox with current config and reattach
```

`claude-sandbox restart --help`:

```
Usage: claude-sandbox restart <target>

  Recreates a sandbox container with the current configuration and
  reattaches VS Code. Use this to apply configuration changes
  (e.g. 'claude-sandbox mounts add') to an existing container.

  <target> may be either:
    - A project path (absolute or relative).
    - A container name (e.g. claude-sandbox-abc12345) from
      'claude-sandbox list'.

  Any existing container for the target is stopped and removed first;
  this ends any running Claude session in that container. If no
  container exists for a path target, you are prompted before one
  is created.
```

---

## Dependencies

- Reuses `open`'s target resolution and the `__claude_sandbox_open_targets` completion
  helper — both already present (`functions/claude-sandbox.fish:685`,
  `completions/claude-sandbox.fish:45`). `restart` keeps its own dispatch block but follows
  `open`'s resolution algorithm. If a shared `_sandbox_resolve_target` helper is later
  introduced, both should use it.

## Out of Scope (v1)

- Per-category drift policies (e.g. warn-only for some categories, silent auto-restart for
  others). v1 uses one policy for all drift: prompt with default restart. The diff is
  category-tagged so this can be added later in the reopen handler alone.
- Auto-restart without any prompt on reopen.
- A migration pass to backfill snapshot labels onto pre-feature containers — they pick up a
  label naturally on their first restart.
- Bulk operations (`restart --all`, `restart --running`).
