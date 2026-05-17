# Per-Project Host Mounts Design

**Date:** 2026-05-18
**Status:** Approved

## Goal

Allow users to mount arbitrary host resources (executables, assets, etc.) into the sandbox container on a per-project basis, while cleaning up the existing config/mount machinery.

## Config File: `configurations.yml`

Replaces `project-creds.json`. Keyed by absolute project path. Stored at `~/.claude-sandbox/configurations.yml`. Gitignored (not committed to the repo).

```yaml
/home/user/my-project:
  credentials:
    type: ssh                                        # or "none"
    keyPath: /home/user/.ssh/id_ed25519_my-project
  mounts:
    - /opt/godot:/usr/local/bin/godot:ro
    - /data/assets:/workspace/assets

/home/user/other-project:
  credentials:
    type: none
```

Parsing and writing uses `yq` — specifically the Ubuntu package (`sudo apt install yq`, kislyuk's implementation, uses jq query syntax). This is distinct from mikefarah's `yq` which has different syntax. All `yq` expressions in this project use jq-compatible syntax.

## `docker-compose.yml` — Static Base

All project-specific mounts are removed. No env var interpolation remains. The file can be used standalone (e.g. for `docker compose build`) without any environment variables.

Named volumes only:

```yaml
services:
  claude-sandbox:
    build: .
    image: claude-sandbox
    container_name: claude-sandbox
    hostname: claude-sandbox
    command: sleep infinity
    security_opt:
      - seccomp=unconfined
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - claude-config:/home/claude/.claude
      - cargo-registry:/home/claude/.cargo/registry
      - cargo-git:/home/claude/.cargo/git
      - rustup-downloads:/home/claude/.rustup/downloads
      - npm-cache:/home/claude/.npm
      - solana-config:/home/claude/.config/solana
      - vscode-server:/home/claude/.vscode-server

volumes:
  claude-config:
  cargo-registry:
  cargo-git:
  rustup-downloads:
  npm-cache:
  solana-config:
  vscode-server:
```

## `docker-compose.override.yml` — Generated Per Launch

Written by `claude-sandbox` to `~/.claude-sandbox/docker-compose.override.yml` on every launch. Gitignored. Docker Compose auto-merges it with the base file (same directory).

Example output:

```yaml
services:
  claude-sandbox:
    working_dir: /workspace/my-project
    volumes:
      - /home/user/my-project:/workspace/my-project
      - /home/user/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
      - /home/user/.ssh/id_ed25519_my-project:/home/claude/.ssh/repo_key:ro
      - /opt/godot:/usr/local/bin/godot:ro
```

Always-included entries:
- `working_dir` — set to `/workspace/$PROJECT_NAME`
- Project bind mount — `$PROJECT_PATH:/workspace/$PROJECT_NAME`
- `.gitconfig` bind mount — `$SANDBOX_DIR/.gitconfig:/home/claude/.gitconfig:ro`

Conditional entries:
- SSH key — only included when `credentials.type == ssh`

Additive entries:
- Each item in `mounts` list for the current project

## `.claude.json` Persistence

The host bind mount for `${HOME}/.claude.json` is removed. Instead, `entrypoint.sh` stores the file inside the `claude-config` named volume and symlinks it:

```sh
# ensure .claude.json exists inside the volume
[ -f /home/claude/.claude/.claude.json ] || echo '{}' > /home/claude/.claude/.claude.json
# symlink so Claude Code finds it at the expected path
ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json
```

The symlink is recreated on each container start. The actual data persists in the named volume across restarts and rebuilds.

**One-time consequence:** existing users must re-login to Claude once after this change. The `${HOME}/.claude.json` on the host is no longer used.

## `entrypoint.sh` Changes

Current entrypoint checks for a non-empty `/home/claude/.ssh/repo_key` and configures SSH. No change to that logic.

Add before `exec "$@"`:
```sh
[ -f /home/claude/.claude/.claude.json ] || echo '{}' > /home/claude/.claude/.claude.json
ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json
```

## `mounts` Subcommand

New subcommand added to `claude-sandbox`, mirroring the `creds` subcommand pattern:

```
claude-sandbox mounts add <source>:<target>[:<options>]
claude-sandbox mounts remove <source>:<target>[:<options>]
claude-sandbox mounts list
claude-sandbox mounts clear
```

All operations act on the current working directory as the project path. Entries are stored in `configurations.yml` under the project's `mounts` key. `clear` removes all entries from the `mounts` list for the current project but leaves the rest of the project's config (credentials, etc.) intact.

## `creds` Subcommand

Unchanged in UX. Internally reads/writes the `credentials` key in `configurations.yml` instead of the root-level keys in `project-creds.json`.

```
claude-sandbox creds set [key-path]
claude-sandbox creds show
claude-sandbox creds clear
claude-sandbox creds list
```

## Fish Helper Functions

Current `_sandbox_creds_*` functions are rewritten to use `yq` against `configurations.yml`:

| Old (jq + JSON) | New (yq + YAML) |
|---|---|
| `_sandbox_creds_read_type` | reads `.["$path"].credentials.type` |
| `_sandbox_creds_read_key` | reads `.["$path"].credentials.keyPath` |
| `_sandbox_creds_write_ssh` | writes `credentials` block |
| `_sandbox_creds_write_none` | writes `credentials.type = none` |
| `_sandbox_creds_delete` | deletes project key |

New helpers:
- `_sandbox_mounts_list <project_path>` — returns list of mount strings
- `_sandbox_mounts_add <project_path> <mount_spec>` — appends to list
- `_sandbox_mounts_remove <project_path> <mount_spec>` — removes matching entry
- `_sandbox_generate_override <project_path> <project_name>` — writes `docker-compose.override.yml`

## `.gitignore` Changes

Add:
```
configurations.yml
docker-compose.override.yml
```

## Removals

- `project-creds.json` — removed from git tracking (`git rm --cached`), deleted from disk after migration
- `.placeholder/` directory — deleted (no longer needed; SSH key mount is conditional in the override)
- `SANDBOX_SSH_KEY_PATH` env var — no longer exported by the fish function

## Migration

1. On first launch after update, the fish function detects `project-creds.json` exists and auto-migrates entries to `configurations.yml`, then deletes the old file.
2. Users re-login to Claude once (one-time, due to `.claude.json` moving into the named volume).

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| `yq` | Read/write `configurations.yml` | `sudo apt install yq` |
| `jq` | (previously used; no longer needed after migration — can be removed from prereqs) | `sudo apt install jq` |
| `xxd` | encode container name for VS Code URI | `sudo apt install xxd` |
