# Global Workspace Configuration Design

**Date:** 2026-05-22
**Status:** Approved

## Problem

On a fresh machine, the `claude-config` Docker volume starts empty. Skills, rules, and other always-on mounts (like `.gitconfig`) are either hardcoded in the fish function or absent entirely. There is no single readable place to see what gets mounted into every sandbox session.

## Goal

Add a `global:` section to `configurations.yml` that serves as the explicit, version-controlled source of truth for all always-on mounts. Per-project mounts append to the global list — they do not replace it.

---

## `configurations.yml` Schema

The file gains two top-level keys: `global` and `projects`. Project paths move from being top-level keys to living under `projects:`.

```yaml
global:
  mounts:
    - ~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
    - ~/.claude-sandbox/skills:/home/claude/.claude/skills:ro
    - ~/.claude-sandbox/rules:/home/claude/.claude/rules:ro

projects:
  /home/you/some-project:
    credentials:
      type: ssh
      keyPath: /home/you/.ssh/id_ed25519_some-project
    mounts:
      - /opt/godot:/usr/local/bin/godot:ro
```

Rules:
- `global.mounts` holds always-on mount specs using `~` notation (expanded at runtime).
- Per-project `mounts` are appended after global mounts; they never replace them.
- `projects` keys are always absolute paths — no collision with `global`.

---

## New Repo Directories

Two directories are added to the repo and mounted read-only into every container:

| Repo path | Container path | Purpose |
|---|---|---|
| `~/.claude-sandbox/skills/` | `/home/claude/.claude/skills/` | Custom Claude Code skills |
| `~/.claude-sandbox/rules/` | `/home/claude/.claude/rules/` | Global Claude Code rules/instructions |

Both are committed with a `.gitkeep` and populated by the user over time.

---

## Fish Function Changes

### `yq` path updates

All project-scoped reads/writes change from `.[$p]` to `.projects[$p]`:

| Function | Old path | New path |
|---|---|---|
| `_sandbox_config_read_creds_type` | `.[$p].credentials.type` | `.projects[$p].credentials.type` |
| `_sandbox_config_read_creds_key` | `.[$p].credentials.keyPath` | `.projects[$p].credentials.keyPath` |
| `_sandbox_config_write_creds_ssh` | `.[$p].credentials = …` | `.projects[$p].credentials = …` |
| `_sandbox_config_write_creds_none` | `.[$p].credentials = …` | `.projects[$p].credentials = …` |
| `_sandbox_config_delete` | `del(.[$p].credentials)` | `del(.projects[$p].credentials)` |
| `_sandbox_mounts_list` | `.[$p].mounts` | `.projects[$p].mounts` |
| `_sandbox_mounts_add` | `.[$p].mounts = …` | `.projects[$p].mounts = …` |
| `_sandbox_mounts_remove` | `.[$p].mounts = …` | `.projects[$p].mounts = …` |
| `_sandbox_mounts_clear` | `del(.[$p].mounts)` | `del(.projects[$p].mounts)` |
| `creds list` display | `to_entries[]` | `.projects | to_entries[]` |

### New global mount helpers

Four new functions mirroring the per-project mount helpers:

- `_sandbox_global_mounts_list` — `yq -r '.global.mounts // [] | .[]'`
- `_sandbox_global_mounts_add` — appends to `.global.mounts`
- `_sandbox_global_mounts_remove` — filters out a spec from `.global.mounts`
- `_sandbox_global_mounts_clear` — `del(.global.mounts)`

### `_sandbox_generate_override` update

Remove the hardcoded `.gitconfig` line. Build volumes as:

1. The project workspace bind: `$project_path:/workspace/$project_name`
2. All global mounts (via `_sandbox_global_mounts_list`, each `~`-expanded)
3. All per-project mounts (via `_sandbox_mounts_list`, each `~`-expanded)

### New `global` subcommand

```
claude-sandbox global mounts add <spec>
claude-sandbox global mounts remove <spec>
claude-sandbox global mounts list
claude-sandbox global mounts clear
```

Follows the same structure as the existing `mounts` subcommand.

---

## Migration

Two migrations run sequentially at launch, each guarded so they are no-ops after the first run:

1. **Existing** `_sandbox_migrate_from_json` — `project-creds.json` → flat `configurations.yml` (already shipped).
2. **New** `_sandbox_migrate_to_nested` — flat `configurations.yml` (project paths as top-level keys) → `global:`/`projects:` schema. Initializes `global.mounts` with the `.gitconfig` entry.

Migration logic for step 2 (pseudo-yq):
```
if .global == null and .projects == null:
  new_file =
    global:
      mounts:
        - ~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
    projects: <current file contents>
```

---

## README Updates

- Volume map: add `skills/` and `rules/` rows.
- Git credentials section: add `claude-sandbox global mounts` to subcommand docs.
- Setup step 3: after copying the fish function, note that `configurations.yml` is pre-populated with default global mounts on first launch.

---

## Out of Scope

- Global credentials (credentials are inherently per-project).
- Per-project overrides of global mounts (append-only is sufficient).
- `global` sections for anything other than `mounts` (no other global config needed now).
