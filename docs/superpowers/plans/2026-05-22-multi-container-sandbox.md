# Multi-container Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `claude-sandbox` so that any number of projects can run in parallel, each in its own container with its own VS Code workspace, by replacing `docker compose up` with a `docker run`-based launch that reads all container config from `configurations.yml`.

**Architecture:** Each project gets a container named `claude-sandbox-<8-char-sha256-of-path>`. All docker runtime configuration (image, security opts, volumes) lives under `global.container` and `projects.<path>.container` in `configurations.yml`. The fish function assembles a `docker run` command at launch time from the merged config. Re-launching in a running project re-attaches VS Code without touching the container. `docker-compose.yml` becomes build-only.

**Tech Stack:** fish shell, yq (jq-compatible YAML processor), Docker Engine, `sha256sum`, `xxd`

**Prerequisite:** The global-workspace-config plan must be fully implemented before starting this plan. `configurations.yml` must have the `global`/`projects` two-level schema in place.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `configurations.yml` | Modify | Add `global.container`; migrate `mounts` → `container.volumes` |
| `docker-compose.yml` | Modify | Strip to build-only |
| `Makefile` | Modify | Remove non-build targets |
| `functions/claude-sandbox.fish` | Modify | All runtime logic changes |
| `completions/claude-sandbox.fish` | Create | Fish tab completions |
| `README.md` | Modify | Update for new UX and subcommands |

---

### Task 1: Migrate `configurations.yml` to the new schema

Adds `global.container` with named volumes + migrated bind mounts; moves per-project `mounts` → `container.volumes`; updates bind-mount paths from `~/.claude-sandbox/` to `${WORKDIR}/`.

**Files:**
- Modify: `configurations.yml`

- [ ] **Step 1: Back up the current file**

```bash
cp ~/.claude-sandbox/configurations.yml ~/.claude-sandbox/configurations.yml.bak
```

- [ ] **Step 2: Add `global.container` with named volumes and migrated bind mounts**

```bash
cd ~/.claude-sandbox
yq -y '.global.container = {
  "image": "claude-sandbox",
  "security_opt": ["seccomp=unconfined"],
  "extra_hosts": ["host.docker.internal:host-gateway"],
  "volumes": (
    ["claude-config:/home/claude/.claude",
     "cargo-registry:/home/claude/.cargo/registry",
     "cargo-git:/home/claude/.cargo/git",
     "rustup-downloads:/home/claude/.rustup/downloads",
     "npm-cache:/home/claude/.npm",
     "solana-config:/home/claude/.config/solana",
     "vscode-server:/home/claude/.vscode-server"] +
    [(.global.mounts // [])[] |
      gsub("~/.claude-sandbox"; "${WORKDIR}") |
      gsub("/home/[^/]+/.claude-sandbox"; "${WORKDIR}")]
  )
}' configurations.yml > /tmp/conf.yml && mv /tmp/conf.yml configurations.yml
```

- [ ] **Step 3: Delete the now-migrated `global.mounts` key**

```bash
yq -y 'del(.global.mounts)' ~/.claude-sandbox/configurations.yml \
  > /tmp/conf.yml && mv /tmp/conf.yml ~/.claude-sandbox/configurations.yml
```

- [ ] **Step 4: Move per-project `mounts` → `container.volumes`**

```bash
yq -y '.projects = (.projects // {} | with_entries(
  .value.container.volumes = (.value.mounts // []) |
  del(.value.mounts)
))' ~/.claude-sandbox/configurations.yml \
  > /tmp/conf.yml && mv /tmp/conf.yml ~/.claude-sandbox/configurations.yml
```

- [ ] **Step 5: Verify the final shape**

```bash
cat ~/.claude-sandbox/configurations.yml
```

Expected shape:
```yaml
global:
  container:
    image: claude-sandbox
    security_opt:
      - seccomp=unconfined
    extra_hosts:
      - host.docker.internal:host-gateway
    volumes:
      - claude-config:/home/claude/.claude
      - cargo-registry:/home/claude/.cargo/registry
      - cargo-git:/home/claude/.cargo/git
      - rustup-downloads:/home/claude/.rustup/downloads
      - npm-cache:/home/claude/.npm
      - solana-config:/home/claude/.config/solana
      - vscode-server:/home/claude/.vscode-server
      - ${WORKDIR}/.gitconfig:/home/claude/.gitconfig:ro
      - ${WORKDIR}/skills:/home/claude/.claude/skills:ro
      - ${WORKDIR}/rules:/home/claude/.claude/rules:ro
projects:
  /home/lhvubtqn/workdir/mattle-fun/godew-valley:
    credentials:
      type: ssh
      keyPath: /home/lhvubtqn/.ssh/id_ed25519_godew-valley
    container:
      volumes:
        - /home/lhvubtqn/.local/bin/godot_v4.6.2:/home/claude/.local/godot
```

Verify: no `global.mounts` key, no `projects.*.mounts` key.

- [ ] **Step 6: Remove backup and commit**

```bash
rm ~/.claude-sandbox/configurations.yml.bak
git -C ~/.claude-sandbox add configurations.yml
git -C ~/.claude-sandbox commit -m "feat: migrate configurations.yml to global.container schema"
```

---

### Task 2: Simplify `docker-compose.yml` and `Makefile`

**Files:**
- Modify: `docker-compose.yml`
- Modify: `Makefile`

- [ ] **Step 1: Replace `docker-compose.yml` content**

Replace the entire file with:

```yaml
services:
  claude-sandbox:
    build: .
    image: claude-sandbox
```

- [ ] **Step 2: Replace `Makefile` content**

Replace the entire file with:

```makefile
COMPOSE = docker compose -f $(HOME)/.claude-sandbox/docker-compose.yml

.PHONY: build build-no-cache

build:
	$(COMPOSE) build

build-no-cache:
	$(COMPOSE) build --no-cache
```

(Tabs required for recipe lines — not spaces.)

- [ ] **Step 3: Verify build target still works**

```bash
cd ~/.claude-sandbox
make build
```

Expected: image builds successfully (or pulls from cache and reports up to date).

- [ ] **Step 4: Remove `docker-compose.override.yml` from `.gitignore`** (it's being eliminated)

Edit `~/.claude-sandbox/.gitignore` — remove the line `docker-compose.override.yml`.

- [ ] **Step 5: Commit**

```bash
git -C ~/.claude-sandbox add docker-compose.yml Makefile .gitignore
git -C ~/.claude-sandbox commit -m "feat: strip docker-compose.yml and Makefile to build-only"
```

---

### Task 3: Add `_sandbox_expand_vars` and `_sandbox_container_name`

Replaces `_sandbox_expand_path` with a version that handles `${WORKDIR}`, `${HOME}`, and `~`. Adds the container-name-from-path helper.

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Source the current function and verify `_sandbox_expand_path` exists**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
functions _sandbox_expand_path
```

Expected: prints the function definition.

- [ ] **Step 2: Replace `_sandbox_expand_path` with `_sandbox_expand_vars`**

In `functions/claude-sandbox.fish`, find and replace the entire `_sandbox_expand_path` function with:

```fish
function _sandbox_expand_vars
    # Expands ${WORKDIR}, ${HOME}, and leading ~ in a path string.
    set -l workdir (dirname (_sandbox_config_file))
    set -l result $argv[1]
    set result (string replace -- '${WORKDIR}' $workdir $result)
    set result (string replace -- '${HOME}' $HOME $result)
    set result (string replace -r '^~/' $HOME/ $result)
    echo $result
end
```

- [ ] **Step 3: Add `_sandbox_container_name` immediately after `_sandbox_expand_vars`**

```fish
function _sandbox_container_name
    # Usage: _sandbox_container_name <absolute_project_path>
    set -l hash (printf '%s' $argv[1] | sha256sum | cut -c1-8)
    echo "claude-sandbox-$hash"
end
```

- [ ] **Step 4: Source and verify `_sandbox_expand_vars`**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
_sandbox_expand_vars '${WORKDIR}/.gitconfig:/home/claude/.gitconfig:ro'
```

Expected: `/home/lhvubtqn/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro`

```fish
_sandbox_expand_vars '~/.ssh/mykey'
```

Expected: `/home/lhvubtqn/.ssh/mykey`

```fish
_sandbox_expand_vars 'claude-config:/home/claude/.claude'
```

Expected: `claude-config:/home/claude/.claude` (unchanged — no variables, named volume)

- [ ] **Step 5: Verify `_sandbox_container_name`**

```fish
_sandbox_container_name /home/lhvubtqn/workdir/mattle-fun/godew-valley
```

Expected: `claude-sandbox-` followed by 8 hex characters. Note the exact value — it must be the same every time for the same path.

Run it twice to confirm it's deterministic:

```fish
_sandbox_container_name /home/lhvubtqn/workdir/mattle-fun/godew-valley
_sandbox_container_name /home/lhvubtqn/workdir/mattle-fun/godew-valley
```

Expected: identical output both times.

```fish
_sandbox_container_name /home/lhvubtqn/workdir/other-project
```

Expected: different 8-char suffix — the two project names must not collide.

- [ ] **Step 6: Update all callers of `_sandbox_expand_path`**

Search for any remaining uses of `_sandbox_expand_path` in the function file:

```bash
grep -n '_sandbox_expand_path' ~/.claude-sandbox/functions/claude-sandbox.fish
```

Replace each occurrence with `_sandbox_expand_vars`. (After the wizard stores paths it currently calls `_sandbox_expand_path` on user input — update those calls too.)

- [ ] **Step 7: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: add _sandbox_expand_vars and _sandbox_container_name"
```

---

### Task 4: Update `_sandbox_mounts_*` to use `container.volumes`

All four per-project mount helpers change their yq path from `.projects[$p].mounts` to `.projects[$p].container.volumes`.

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Verify current per-project mount reads correctly before changing**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
_sandbox_mounts_list /home/lhvubtqn/workdir/mattle-fun/godew-valley
```

Expected: `/home/lhvubtqn/.local/bin/godot_v4.6.2:/home/claude/.local/godot`

- [ ] **Step 2: Replace `_sandbox_mounts_list`**

```fish
function _sandbox_mounts_list
    set -l f (_sandbox_config_file)
    test -f $f; or return
    yq -r --arg p $argv[1] '.projects[$p].container.volumes // [] | .[]' $f 2>/dev/null
end
```

- [ ] **Step 3: Replace `_sandbox_mounts_add`**

```fish
function _sandbox_mounts_add
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.projects[$p].container.volumes = ((.projects[$p].container.volumes // []) + [$m])' $f > $tmp
    and mv $tmp $f
end
```

- [ ] **Step 4: Replace `_sandbox_mounts_remove`**

```fish
function _sandbox_mounts_remove
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l count (yq -r --arg p $argv[1] '.projects[$p].container.volumes | length' $f 2>/dev/null)
    test "$count" -gt 0 2>/dev/null; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.projects[$p].container.volumes = [(.projects[$p].container.volumes // [])[] | select(. != $m)]' $f > $tmp
    and mv $tmp $f
end
```

- [ ] **Step 5: Replace `_sandbox_mounts_clear`**

```fish
function _sandbox_mounts_clear
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] 'del(.projects[$p].container.volumes)' $f > $tmp
    and mv $tmp $f
end
```

- [ ] **Step 6: Source and verify all four helpers**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
_sandbox_mounts_list /home/lhvubtqn/workdir/mattle-fun/godew-valley
```

Expected: `/home/lhvubtqn/.local/bin/godot_v4.6.2:/home/claude/.local/godot` (same as before the change)

```fish
_sandbox_mounts_add /home/lhvubtqn/workdir/mattle-fun/godew-valley "/tmp/test:/tmp/test:ro"
_sandbox_mounts_list /home/lhvubtqn/workdir/mattle-fun/godew-valley
```

Expected: two lines — original godot mount plus `/tmp/test:/tmp/test:ro`.

```fish
_sandbox_mounts_remove /home/lhvubtqn/workdir/mattle-fun/godew-valley "/tmp/test:/tmp/test:ro"
_sandbox_mounts_list /home/lhvubtqn/workdir/mattle-fun/godew-valley
```

Expected: back to one line (godot only).

- [ ] **Step 7: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: migrate _sandbox_mounts_* to container.volumes path"
```

---

### Task 5: Update `_sandbox_global_mounts_*` to use `global.container.volumes`

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Verify current global mount list before changing**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
_sandbox_global_mounts_list
```

Expected: three lines — `.gitconfig`, `skills`, `rules` entries (now with `${WORKDIR}` after Task 1 migration).

- [ ] **Step 2: Replace `_sandbox_global_mounts_list`**

```fish
function _sandbox_global_mounts_list
    set -l f (_sandbox_config_file)
    test -f $f; or return
    yq -r '.global.container.volumes // [] | .[]' $f 2>/dev/null
end
```

- [ ] **Step 3: Replace `_sandbox_global_mounts_add`**

```fish
function _sandbox_global_mounts_add
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg m $argv[1] \
        '.global.container.volumes = ((.global.container.volumes // []) + [$m])' $f > $tmp
    and mv $tmp $f
end
```

- [ ] **Step 4: Replace `_sandbox_global_mounts_remove`**

```fish
function _sandbox_global_mounts_remove
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg m $argv[1] \
        '.global.container.volumes = [(.global.container.volumes // [])[] | select(. != $m)]' $f > $tmp
    and mv $tmp $f
end
```

- [ ] **Step 5: Replace `_sandbox_global_mounts_clear`**

```fish
function _sandbox_global_mounts_clear
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y 'del(.global.container.volumes)' $f > $tmp
    and mv $tmp $f
end
```

- [ ] **Step 6: Source and verify**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
_sandbox_global_mounts_list
```

Expected: all volumes under `global.container.volumes` — named volumes followed by bind mounts (10 lines total: 7 named + 3 bind).

```fish
_sandbox_global_mounts_add "/tmp/test:/tmp/test:ro"
_sandbox_global_mounts_list | tail -1
```

Expected: `/tmp/test:/tmp/test:ro`

```fish
_sandbox_global_mounts_remove "/tmp/test:/tmp/test:ro"
_sandbox_global_mounts_list | wc -l
```

Expected: `10` (back to original count)

- [ ] **Step 7: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: migrate _sandbox_global_mounts_* to global.container.volumes"
```

---

### Task 6: Add `_sandbox_docker_run` function

Builds and executes the `docker run` command from the merged effective config.

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Add `_sandbox_docker_run` after `_sandbox_container_name`**

```fish
function _sandbox_docker_run
    # Usage: _sandbox_docker_run <container_name> <project_path> <project_name>
    set -l container_name $argv[1]
    set -l project_path $argv[2]
    set -l project_name $argv[3]
    set -l f (_sandbox_config_file)

    # Resolve image (project overrides global)
    set -l image (yq -r --arg p $project_path \
        '(.projects[$p].container.image // .global.container.image // "claude-sandbox")' $f)

    set -l args -d \
        --name $container_name \
        --hostname claude-sandbox \
        --label "claude-sandbox.project=$project_path"

    # security_opt: global then project
    for opt in (yq -r --arg p $project_path \
        '((.global.container.security_opt // []) + (.projects[$p].container.security_opt // [])) | .[]' $f 2>/dev/null)
        set args $args --security-opt $opt
    end

    # extra_hosts: global then project
    for host in (yq -r --arg p $project_path \
        '((.global.container.extra_hosts // []) + (.projects[$p].container.extra_hosts // [])) | .[]' $f 2>/dev/null)
        set args $args --add-host $host
    end

    # volumes: global then project, with variable expansion
    for vol in (yq -r --arg p $project_path \
        '((.global.container.volumes // []) + (.projects[$p].container.volumes // [])) | .[]' $f 2>/dev/null)
        set args $args -v (_sandbox_expand_vars $vol)
    end

    # SSH deploy key (credentials-managed, not in volumes list)
    set -l creds_type (_sandbox_config_read_creds_type $project_path)
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_expand_vars (_sandbox_config_read_creds_key $project_path))
        set args $args -v "$key_path:/home/claude/.ssh/deploy_key:ro"
    end

    set args $args \
        --workdir /workspace/$project_name \
        --entrypoint /entrypoint.sh

    docker run $args $image sleep infinity
end
```

- [ ] **Step 2: Source and do a dry-run (print the args without running)**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish

# Inspect what _sandbox_docker_run would pass to docker run by tracing it:
set -l PROJECT_PATH /home/lhvubtqn/workdir/mattle-fun/godew-valley
set -l PROJECT_NAME godew-valley
set -l container_name (_sandbox_container_name $PROJECT_PATH)
set -l f (_sandbox_config_file)

# Print the volumes that would be mounted
yq -r --arg p $PROJECT_PATH \
    '((.global.container.volumes // []) + (.projects[$p].container.volumes // [])) | .[]' $f
```

Expected: 10 lines — 7 named volumes then 3 bind mounts from global, then the godot project mount.

- [ ] **Step 3: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: add _sandbox_docker_run function"
```

---

### Task 7: Replace launch block; remove dead functions

Replaces `docker compose up --force-recreate` with the idempotent `docker run`/`docker start`/reattach flow. Removes `_sandbox_generate_override`, `_sandbox_migrate_from_json`, `_sandbox_migrate_to_nested`.

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Delete `_sandbox_migrate_from_json`**

Remove the entire function from `functions/claude-sandbox.fish`.

- [ ] **Step 2: Delete `_sandbox_migrate_to_nested`**

Remove the entire function from `functions/claude-sandbox.fish`.

- [ ] **Step 3: Delete `_sandbox_generate_override`**

Remove the entire function from `functions/claude-sandbox.fish`.

- [ ] **Step 4: Replace the launch flow in the `claude-sandbox` function body**

Find the block that starts with `# --- launch flow ---` and replace from there through the `code --folder-uri` line with:

```fish
    # --- launch flow ---
    if not docker info > /dev/null 2>&1
        echo "Error: Docker is not running. Please start Docker Desktop first."
        return 1
    end

    # Resolve credentials for this project
    set -l creds_type (_sandbox_config_read_creds_type $PROJECT_PATH)
    if test -z "$creds_type"
        _sandbox_creds_wizard $PROJECT_PATH $PROJECT_NAME
        or return 1
        set creds_type (_sandbox_config_read_creds_type $PROJECT_PATH)
    end

    # Verify SSH key exists if configured
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_expand_vars (_sandbox_config_read_creds_key $PROJECT_PATH))
        if not test -f $key_path
            echo "Error: SSH key not found: $key_path"
            echo "Run 'claude-sandbox creds set' to reconfigure."
            return 1
        end
    end

    set -l container_name (_sandbox_container_name $PROJECT_PATH)
    set -l container_status (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)

    switch $container_status
        case running
            echo "Attaching to running sandbox for $PROJECT_NAME..."
        case exited created paused
            echo "Starting sandbox for $PROJECT_NAME..."
            docker start $container_name
            or begin
                echo "Error: Failed to start container."
                return 1
            end
        case '*'
            echo "Creating new sandbox for $PROJECT_NAME..."
            _sandbox_docker_run $container_name $PROJECT_PATH $PROJECT_NAME
            or begin
                echo "Error: Failed to create container."
                return 1
            end
    end

    set -l container_json "{\"containerName\":\"/$container_name\"}"
    set -l encoded (printf '%s' $container_json | xxd -p | tr -d '\n')
    code --folder-uri "vscode-remote://attached-container+$encoded/workspace/$PROJECT_NAME"
```

- [ ] **Step 5: Remove the two migration calls from the launch flow**

Find and remove these two lines (they were called at the top of the launch block):

```fish
    _sandbox_migrate_from_json
    _sandbox_migrate_to_nested
```

- [ ] **Step 6: Source and verify no dead function references remain**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
```

Expected: no errors.

```bash
grep -n '_sandbox_migrate_from_json\|_sandbox_migrate_to_nested\|_sandbox_generate_override\|_sandbox_expand_path' \
  ~/.claude-sandbox/functions/claude-sandbox.fish
```

Expected: no output (all references removed).

- [ ] **Step 7: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: replace compose launch with idempotent docker run flow"
```

---

### Task 8: Add `stop` and `list` subcommands

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Add `stop` subcommand block**

In the `claude-sandbox` function body, add this block immediately before the `# --- creds subcommand ---` block:

```fish
    # --- stop subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = stop
        if contains -- --help $argv
            echo "Usage: claude-sandbox stop [--rm]"
            echo ""
            echo "  Stops the container for the current project."
            echo "  --rm    Also remove the container after stopping."
            return 0
        end
        set -l remove false
        if contains -- --rm $argv
            set remove true
        end
        set -l container_name (_sandbox_container_name $PROJECT_PATH)
        if not docker inspect $container_name > /dev/null 2>&1
            echo "No container found for $PROJECT_PATH"
            return 1
        end
        docker stop $container_name
        or return 1
        if test "$remove" = true
            docker rm $container_name
        end
        return
    end
```

- [ ] **Step 2: Add `list` subcommand block**

Immediately after the `stop` block:

```fish
    # --- list subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = list
        if contains -- --help $argv
            echo "Usage: claude-sandbox list"
            echo ""
            echo "  Lists all claude-sandbox containers and their project paths."
            return 0
        end
        docker ps -a \
            --filter "label=claude-sandbox.project" \
            --format "table {{.Names}}\t{{.Label \"claude-sandbox.project\"}}\t{{.Status}}"
        return
    end
```

- [ ] **Step 3: Source and verify `stop` help**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
claude-sandbox stop --help
```

Expected: usage string with `--rm` description, exits 0.

- [ ] **Step 4: Verify `list` with no running sandbox containers**

```fish
claude-sandbox list
```

Expected: header row only (or empty output — no claude-sandbox containers running yet).

- [ ] **Step 5: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: add stop and list subcommands"
```

---

### Task 9: Add `--help` to all remaining subcommands and top level

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Add top-level `--help` check**

At the very top of the `claude-sandbox` function body (before any subcommand checks), add:

```fish
    # --- top-level --help ---
    if contains -- --help $argv; and test (count $argv) -eq 1
        echo "Usage: claude-sandbox [--help]"
        echo "       claude-sandbox <subcommand> [--help]"
        echo ""
        echo "Subcommands:"
        printf "  %-34s%s\n" "(no args)"            "Launch sandbox for current project"
        printf "  %-34s%s\n" "stop [--rm]"           "Stop this project's container; --rm also removes it"
        printf "  %-34s%s\n" "list"                  "List all sandbox containers"
        printf "  %-34s%s\n" "creds <action>"        "Manage per-project SSH credentials"
        printf "  %-34s%s\n" "mounts <action>"       "Manage per-project volume entries"
        printf "  %-34s%s\n" "global mounts <action>" "Manage always-on global volume entries"
        echo ""
        echo "Run 'claude-sandbox <subcommand> --help' for subcommand usage."
        return 0
    end
```

- [ ] **Step 2: Add `--help` to the `creds` subcommand**

Inside the `# --- creds subcommand ---` block, immediately after the `set -l action $argv[2]` line, add:

```fish
        if contains -- --help $argv
            echo "Usage: claude-sandbox creds {set [key-path]|show|clear|list}"
            echo ""
            printf "  %-22s%s\n" "set [key-path]" "Configure SSH key (runs wizard if no path given)"
            printf "  %-22s%s\n" "show"           "Print saved credential for current project"
            printf "  %-22s%s\n" "clear"          "Remove saved credential (will prompt on next launch)"
            printf "  %-22s%s\n" "list"           "List all saved project credentials"
            return 0
        end
```

- [ ] **Step 3: Add `--help` to the `mounts` subcommand**

Inside the `# --- mounts subcommand ---` block, immediately after `set -l action $argv[2]`, add:

```fish
        if contains -- --help $argv
            echo "Usage: claude-sandbox mounts {add <spec>|remove <spec>|list|clear}"
            echo ""
            printf "  %-24s%s\n" "add <spec>"    "Add a volume entry for current project"
            printf "  %-24s%s\n" "remove <spec>" "Remove a volume entry"
            printf "  %-24s%s\n" "list"          "Show all volume entries for current project"
            printf "  %-24s%s\n" "clear"         "Remove all volume entries for current project"
            echo ""
            echo "  <spec> format: <host-path>:<container-path>[:<options>]"
            echo "  Supports \${WORKDIR}, \${HOME}, and ~ in host paths."
            return 0
        end
```

- [ ] **Step 4: Add `--help` to the `global` subcommand**

Inside the `# --- global subcommand ---` block, immediately after entering the block (before the `mounts` check), add:

```fish
        if contains -- --help $argv
            echo "Usage: claude-sandbox global mounts {add <spec>|remove <spec>|list|clear}"
            echo ""
            printf "  %-24s%s\n" "add <spec>"    "Add a volume entry applied to every container"
            printf "  %-24s%s\n" "remove <spec>" "Remove a global volume entry"
            printf "  %-24s%s\n" "list"          "Show all global volume entries"
            printf "  %-24s%s\n" "clear"         "Remove all global volume entries"
            return 0
        end
```

- [ ] **Step 5: Source and verify all help strings**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
claude-sandbox --help
```

Expected: usage block with 6 subcommands listed.

```fish
claude-sandbox creds --help
claude-sandbox mounts --help
claude-sandbox global --help
claude-sandbox stop --help
claude-sandbox list --help
```

Expected: each prints its own usage string and exits 0.

- [ ] **Step 6: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: add --help to all subcommands"
```

---

### Task 10: Add fish completions

**Files:**
- Create: `completions/claude-sandbox.fish`

- [ ] **Step 1: Create the completions file**

Create `~/.claude-sandbox/completions/claude-sandbox.fish` with:

```fish
# Tab completions for claude-sandbox

set -l subcommands stop list creds mounts global

# No file completion at top level
complete -c claude-sandbox -f

# Top-level: --help and subcommands (only when no subcommand seen yet)
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -l help -d 'Show usage and exit'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a stop   -d 'Stop this project'\''s container'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a list   -d 'List all sandbox containers'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a creds  -d 'Manage per-project SSH credentials'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a mounts -d 'Manage per-project volume entries'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a global -d 'Manage global configuration'

# stop
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from stop" \
    -l rm   -d 'Also remove the container after stopping'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from stop" \
    -l help -d 'Show usage'

# list
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from list" \
    -l help -d 'Show usage'

# creds actions
set -l creds_actions set show clear list
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from creds; and not __fish_seen_subcommand_from $creds_actions" \
    -a set   -d 'Configure SSH key'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from creds; and not __fish_seen_subcommand_from $creds_actions" \
    -a show  -d 'Show current credential'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from creds; and not __fish_seen_subcommand_from $creds_actions" \
    -a clear -d 'Remove saved credential'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from creds; and not __fish_seen_subcommand_from $creds_actions" \
    -a list  -d 'List all project credentials'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from creds" \
    -l help -d 'Show usage'

# mounts actions (not under global)
set -l mount_actions add remove list clear
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global; and not __fish_seen_subcommand_from $mount_actions" \
    -a add    -d 'Add a volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global; and not __fish_seen_subcommand_from $mount_actions" \
    -a remove -d 'Remove a volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global; and not __fish_seen_subcommand_from $mount_actions" \
    -a list   -d 'List volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global; and not __fish_seen_subcommand_from $mount_actions" \
    -a clear  -d 'Clear all volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global" \
    -l help -d 'Show usage'

# global → mounts → actions
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and not __fish_seen_subcommand_from mounts" \
    -a mounts -d 'Manage global volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and __fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a add    -d 'Add a global volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and __fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a remove -d 'Remove a global volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and __fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a list   -d 'List global volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and __fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a clear  -d 'Clear all global volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global" \
    -l help -d 'Show usage'
```

- [ ] **Step 2: Install the completions file**

```bash
cp ~/.claude-sandbox/completions/claude-sandbox.fish ~/.config/fish/completions/claude-sandbox.fish
```

- [ ] **Step 3: Reload completions**

```fish
fish --command "complete --do-complete 'claude-sandbox '" | head -20
```

Expected: list of subcommands with descriptions (`stop`, `list`, `creds`, `mounts`, `global`, `--help`).

```fish
fish --command "complete --do-complete 'claude-sandbox stop '" | head -10
```

Expected: `--rm` and `--help` with descriptions.

```fish
fish --command "complete --do-complete 'claude-sandbox creds '" | head -10
```

Expected: `set`, `show`, `clear`, `list`, `--help`.

- [ ] **Step 4: Commit**

```bash
git -C ~/.claude-sandbox add completions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: add fish tab completions for claude-sandbox"
```

---

### Task 11: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update Setup step 3**

Find the step:
```
**3. Install the fish function**
```

Update the `cp` command to also install the completions file:

```markdown
**3. Install the fish function and completions**

```bash
mkdir -p ~/.config/fish/functions ~/.config/fish/completions
cp ~/.claude-sandbox/functions/claude-sandbox.fish ~/.config/fish/functions/
cp ~/.claude-sandbox/completions/claude-sandbox.fish ~/.config/fish/completions/
```

`configurations.yml` ships with defaults in the repo. Existing installs with an older flat-schema file are auto-migrated on first launch.
```

- [ ] **Step 2: Update the Usage section**

Find the bullet list under "This will:":

```markdown
This will:
1. Start (or restart) the container with your project mounted at `/workspace/your-project`
2. Open VS Code attached to the running container
```

Replace with:

```markdown
This will:
1. Start a new container for this project (or reattach if one is already running)
2. Open VS Code attached to that container

Each project gets its own container — running `claude-sandbox` from a second project opens a second VS Code window without touching the first.
```

- [ ] **Step 3: Update the "How it works" section**

Replace the existing bullet list with:

```markdown
- **Per-project containers**: each project runs in a dedicated container named `claude-sandbox-<hash>` where the hash is derived from the project path. Running `claude-sandbox` in a project that is already open re-attaches VS Code without restarting the container or interrupting any running Claude session.
- **Project mount**: your current folder binds to `/workspace/<project-name>`. Each project gets a unique path so `claude -r` sessions stay scoped correctly.
- **Claude auth**: the `claude-config` named volume holds your subscription login — it is shared across all project containers.
- **Persistent caches**: named Docker volumes keep Cargo, npm, Solana config, and the VS Code Server across restarts and image rebuilds. All project containers share these caches.
- **Host networking**: services running on the host (e.g. Godot MCP) are reachable inside the container at `host.docker.internal:<port>`.
- **Per-repo SSH credentials**: on first launch in a project, a wizard prompts you to generate a deploy key, use an existing key, or skip. Your choice is saved per project path — subsequent launches are silent. See [Git credentials](#git-credentials) below.
```

- [ ] **Step 4: Add "Managing containers" section**

Add a new `## Managing containers` section after the `## Usage` section:

```markdown
## Managing containers

Each project runs in its own container that persists until explicitly stopped.

```bash
claude-sandbox stop        # stop this project's container (from project dir)
claude-sandbox stop --rm   # stop and remove
claude-sandbox list        # list all sandbox containers with status
```

`list` shows all containers created by `claude-sandbox`, their project paths, and their current status.
```

- [ ] **Step 5: Update the Global workspace section**

Replace `global.mounts` references with `global.container.volumes`. Find:

```markdown
Always-on mounts (applied to every sandbox session regardless of project) are listed in `configurations.yml` under `global.mounts`.
```

Replace with:

```markdown
Always-on volume entries (applied to every container regardless of project) are listed in `configurations.yml` under `global.container.volumes`.
```

Update the YAML example block to match the new schema:

```yaml
global:
  container:
    volumes:
      - ${WORKDIR}/.gitconfig:/home/claude/.gitconfig:ro
      - ${WORKDIR}/skills:/home/claude/.claude/skills:ro
      - ${WORKDIR}/rules:/home/claude/.claude/rules:ro
```

- [ ] **Step 6: Update the Deferred section**

Remove the "Multi-agent / swarm setup" bullet (now supported). Update to:

```markdown
## Deferred

- Per-stack profiles (different extension sets for different languages)
- Per-project devcontainer configs
```

- [ ] **Step 7: Commit**

```bash
git -C ~/.claude-sandbox add README.md
git -C ~/.claude-sandbox commit -m "docs: update README for multi-container UX"
```

---

### Task 12: Install and end-to-end smoke test

- [ ] **Step 1: Install the updated fish function and completions**

```bash
cp ~/.claude-sandbox/functions/claude-sandbox.fish ~/.config/fish/functions/claude-sandbox.fish
cp ~/.claude-sandbox/completions/claude-sandbox.fish ~/.config/fish/completions/claude-sandbox.fish
```

- [ ] **Step 2: Open a new fish shell and verify the function loads**

```fish
type claude-sandbox
```

Expected: prints the function definition (not "not found").

- [ ] **Step 3: Verify `--help`**

```fish
claude-sandbox --help
```

Expected: usage block listing all subcommands.

- [ ] **Step 4: Verify `list` shows no stale containers**

```fish
claude-sandbox list
```

Expected: header row only, or any existing containers from previous runs.

- [ ] **Step 5: Launch a project for the first time**

```bash
cd ~/workdir/mattle-fun/godew-valley
claude-sandbox
```

Expected:
- Prints "Creating new sandbox for godew-valley..."
- `docker ps` shows a container named `claude-sandbox-<hash>`
- VS Code opens attached to that container

- [ ] **Step 6: Verify the container has the correct labels and volumes**

```fish
set -l container_name (_sandbox_container_name (pwd))
docker inspect $container_name --format '{{.Config.Labels}}'
```

Expected: shows `claude-sandbox.project=/home/lhvubtqn/workdir/mattle-fun/godew-valley`.

```bash
docker inspect $container_name --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
```

Expected: lists all named volumes and bind mounts including `.gitconfig`, `skills`, `rules`, and the godot mount.

- [ ] **Step 7: Re-launch in the same project (idempotency test)**

```bash
cd ~/workdir/mattle-fun/godew-valley
claude-sandbox
```

Expected:
- Prints "Attaching to running sandbox for godew-valley..."
- No new container is created (`docker ps` still shows the same container)
- VS Code re-opens attached to the same container

- [ ] **Step 8: Launch a second project simultaneously**

```bash
cd ~  # or any other project directory
mkdir -p /tmp/test-project
cd /tmp/test-project
claude-sandbox
```

Expected:
- Prints "Creating new sandbox for test-project..."
- `docker ps` shows two containers: `claude-sandbox-<hash1>` and `claude-sandbox-<hash2>`
- VS Code opens a second window

- [ ] **Step 9: Verify `claude-sandbox list` shows both containers**

```fish
claude-sandbox list
```

Expected: two rows, each showing container name, project path, and status (Up ...).

- [ ] **Step 10: Stop and remove the test container**

```bash
cd /tmp/test-project
claude-sandbox stop --rm
```

Expected: container stops and is removed. `claude-sandbox list` shows one container remaining.

- [ ] **Step 11: Verify the first project's container is still running**

```bash
claude-sandbox list
```

Expected: the godew-valley container is still `Up`.

- [ ] **Step 12: Clean up and commit if any last changes**

```bash
cd /tmp && rm -rf /tmp/test-project
git -C ~/.claude-sandbox status
```

If any files are modified, commit them before closing out.
