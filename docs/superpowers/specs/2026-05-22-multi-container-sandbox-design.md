# Multi-container Sandbox Design

**Date:** 2026-05-22
**Status:** Approved

## Problem

The current implementation uses a single container (`container_name: claude-sandbox`) and a single `docker-compose.override.yml` that is overwritten on every launch. Running `claude-sandbox` from a second project kills the first project's container and session. Only one VS Code workspace can be open at a time.

## Goal

Allow any number of projects to run simultaneously, each in its own isolated container with its own VS Code workspace attached, sharing build caches. Re-launching `claude-sandbox` in a project that is already running re-attaches VS Code without disturbing the running Claude session.

---

## Decisions

| Question | Decision |
|---|---|
| Isolation model | One container per project |
| Build caches | Shared named volumes across all containers |
| Container lifecycle | Persist until explicitly stopped |
| Launch mechanism | `docker run` (not compose); compose kept for build only |
| Container naming | `claude-sandbox-<8-char sha256 of project path>` |
| Config source of truth | `configurations.yml` — all docker runtime config lives here |
| `extra_hosts` | Keep `host.docker.internal:host-gateway` (required on WSL2) |
| Migration functions | Removed — new design assumes `global`/`projects` schema in place |

---

## `configurations.yml` Schema

Extends the existing `global`/`projects` schema (from the global-workspace-config spec) with a `container` section under both `global` and `projects`. All docker runtime configuration moves here from `docker-compose.yml`.

```yaml
global:
  container:
    image: claude-sandbox
    security_opt:
      - seccomp=unconfined
    extra_hosts:
      - host.docker.internal:host-gateway
    volumes:
      # named volumes (shared caches — all project containers share these)
      - claude-config:/home/claude/.claude
      - cargo-registry:/home/claude/.cargo/registry
      - cargo-git:/home/claude/.cargo/git
      - rustup-downloads:/home/claude/.rustup/downloads
      - npm-cache:/home/claude/.npm
      - solana-config:/home/claude/.config/solana
      - vscode-server:/home/claude/.vscode-server
      # always-on bind mounts
      - ${WORKDIR}/.gitconfig:/home/claude/.gitconfig:ro
      - ${WORKDIR}/skills:/home/claude/.claude/skills:ro
      - ${WORKDIR}/rules:/home/claude/.claude/rules:ro

projects:
  /home/user/some-project:
    credentials:
      type: ssh
      keyPath: ${HOME}/.ssh/id_ed25519_some-project
    container:
      volumes:
        - /opt/godot:/usr/local/bin/godot:ro
```

### Path variables

Expanded by the fish function before any path reaches `docker run`:

| Variable | Expands to |
|---|---|
| `${WORKDIR}` | Directory containing `configurations.yml` (the repo root) |
| `${HOME}` | User's home directory |
| `~` | User's home directory |

Applied in order: `${WORKDIR}` first, then `${HOME}`, then `~`.

### Merge rules

When building the effective config for a project, global and project `container` sections are merged:

- **Scalars** (e.g. `image`): project value overrides global
- **Lists** (`volumes`, `security_opt`, `extra_hosts`): project entries appended after global entries; no deduplication
- `credentials` is project-only — no global credentials concept

### Named volume vs bind mount detection

Variable expansion is applied to every `volumes` entry first. After expansion, an entry is a bind mount if its host-side path (left of the first `:`) starts with `/`. Named volumes never have a leading `/` in the host portion, so a single check suffices. Bind mounts use the already-expanded path; named volumes are passed to `-v` as-is.

---

## Container Identity

```
container_name = claude-sandbox-<first 8 chars of sha256(absolute project path)>
```

The project path is stored as a Docker label at run time so `list` can reverse-map container → project:

```
--label claude-sandbox.project=<absolute project path>
```

---

## Launch Flow

Replaces `docker compose up --force-recreate`. `docker-compose.override.yml` is eliminated.

```
1. Compute container_name = claude-sandbox-<hash(PROJECT_PATH)>
2. docker inspect <container_name>
   → exit 1 (not found):  docker run   (new container, full flag set)
   → found, stopped:       docker start <container_name>
   → found, running:       skip — go directly to step 3
3. code --folder-uri vscode-remote://attached-container+<hex-encoded container_name>/workspace/<PROJECT_NAME>
```

The `docker run` command is assembled from the merged effective config:

```
docker run -d \
  --name <container_name> \
  --hostname claude-sandbox \
  --label claude-sandbox.project=<PROJECT_PATH> \
  --security-opt <each security_opt> \
  --add-host <each extra_hosts entry> \
  -v <each volumes entry, bind-mount paths expanded> \
  --workdir /workspace/<PROJECT_NAME> \
  --entrypoint /entrypoint.sh \
  <image> sleep infinity
```

---

## `docker-compose.yml` After

Compose is build-only. All runtime config moves to `configurations.yml`.

```yaml
services:
  claude-sandbox:
    build: .
    image: claude-sandbox
```

---

## Makefile After

`down`, `shell`, `logs`, and `clean` are removed — they hardcode the old single container name and are no longer meaningful. Per-project container management goes through `claude-sandbox stop` and `claude-sandbox list`.

```makefile
COMPOSE = docker compose -f $(HOME)/.claude-sandbox/docker-compose.yml

.PHONY: build build-no-cache

build:
	$(COMPOSE) build

build-no-cache:
	$(COMPOSE) build --no-cache
```

---

## Fish Function Changes

### New helper: `_sandbox_expand_vars`

Replaces `_sandbox_expand_path`. Applies three substitutions in order:

```fish
function _sandbox_expand_vars
    set -l workdir (dirname (_sandbox_config_file))
    string replace -r '\$\{WORKDIR\}' $workdir $argv[1] \
    | string replace -r '\$\{HOME\}' $HOME \
    | string replace -r '^~/' $HOME/
end
```

### New helper: `_sandbox_container_name`

```fish
function _sandbox_container_name
    # Usage: _sandbox_container_name <project_path>
    set -l hash (printf '%s' $argv[1] | sha256sum | cut -c1-8)
    echo "claude-sandbox-$hash"
end
```

### New helper: `_sandbox_build_volumes`

Reads the merged volumes list and emits `-v <entry>` flags, expanding path variables on bind mounts.

### Updated `_sandbox_generate_override` → removed

The override file generation function is deleted entirely. The launch flow calls `docker run` / `docker start` directly.

### Updated launch block

```fish
set -l container_name (_sandbox_container_name $PROJECT_PATH)
set -l status (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)

switch $status
    case running
        # already up — fall through to VS Code
    case exited created paused
        docker start $container_name
        or return 1
    case '*'
        # not found — run fresh
        _sandbox_docker_run $container_name $PROJECT_PATH $PROJECT_NAME
        or return 1
end

set container_json "{\"containerName\":\"/$container_name\"}"
set encoded (printf '%s' $container_json | xxd -p | tr -d '\n')
code --folder-uri "vscode-remote://attached-container+$encoded/workspace/$PROJECT_NAME"
```

### Removed functions

- `_sandbox_migrate_from_json` — removed
- `_sandbox_migrate_to_nested` — removed (caller is assumed to have already run the global-workspace-config migration)
- `_sandbox_generate_override` — removed

---

## New Subcommands

### `claude-sandbox stop [--rm]`

Stops this project's container. `--rm` also removes it.

```fish
set -l container_name (_sandbox_container_name $PROJECT_PATH)
docker stop $container_name
if test "$remove" = true
    docker rm $container_name
end
```

### `claude-sandbox list`

Lists all running (or stopped) sandbox containers with their mapped project path and status.

```
docker ps -a --filter label=claude-sandbox.project \
           --format "table {{.Names}}\t{{.Label \"claude-sandbox.project\"}}\t{{.Status}}"
```

### `claude-sandbox --help` and `<subcommand> --help`

Every subcommand checks for `--help` before doing any work and prints a usage summary, then exits 0.

Top-level `--help` output:

```
Usage: claude-sandbox [--help]
       claude-sandbox <subcommand> [--help]

Subcommands:
  (no args)            Launch sandbox for current project
  stop [--rm]          Stop this project's container; --rm also removes it
  list                 List all sandbox containers
  creds <action>       Manage per-project SSH credentials
  mounts <action>      Manage per-project bind mounts
  global mounts <action>  Manage always-on global bind mounts

Run 'claude-sandbox <subcommand> --help' for subcommand usage.
```

---

## Fish Completions

New file: `completions/claude-sandbox.fish` — copied to `~/.config/fish/completions/` alongside the function.

Covers:
- Top-level subcommands with descriptions
- `--help` and `--rm` flags
- Second-level actions for `creds`, `mounts`, `global mounts`
- `global` subcommand routing to `mounts`

---

## README Updates

- **Usage section**: update "Start (or restart)" wording — second launch now re-attaches rather than restarts
- **How it works**: add bullet explaining per-project container naming and idempotent launch
- **Volume map**: remove SSH deploy key row note about override file; update to reflect `configurations.yml` as source of truth
- **Git credentials section**: remove reference to generated override file
- **Global workspace section**: update `global.mounts` path references to `global.container.volumes`
- **Rebuilding section**: keep as-is (still uses compose build)
- **Deferred section**: remove "Multi-agent / swarm setup" (now supported by this feature)
- Add new **Managing containers** section documenting `stop` and `list`

---

## Out of Scope

- Per-project `image` override (all projects use the same image)
- Automatic container cleanup on VS Code window close
- `global container` management subcommand (edit `configurations.yml` directly for now)
- Windows (non-WSL2) support
