# Per-Project Host Mounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `project-creds.json` with `configurations.yml`, add per-project host mount support via a `mounts` subcommand, and generate a `docker-compose.override.yml` on launch instead of embedding project-specific mounts in the static compose file.

**Architecture:** The fish function rewrites its config backend from jq+JSON to yq+YAML, adds helpers for mount management, generates a `docker-compose.override.yml` on every launch (auto-merged by Docker Compose), and auto-migrates existing `project-creds.json` on first run. `docker-compose.yml` becomes fully static with no env var interpolation.

**Tech Stack:** fish shell, `yq` (Ubuntu package — kislyuk's implementation, jq-compatible syntax), `jq` (used only for one-time migration), Docker Compose v2

---

## File Map

| File | Action | What changes |
|---|---|---|
| `functions/claude-sandbox.fish` | Modify | Full rewrite: yq config helpers, mounts helpers, override generator, migration, mounts subcommand, launch flow cleanup |
| `docker-compose.yml` | Modify | Remove all env var slots, project mounts, .claude.json mount, gitconfig mount, SSH key mount. Named volumes only. |
| `Makefile` | Modify | Remove `PROJECT_PATH=/tmp PROJECT_NAME=build` env vars from build targets |
| `entrypoint.sh` | Modify | Add .claude.json symlink creation before `exec "$@"` |
| `.gitignore` | Modify | Add `configurations.yml` and `docker-compose.override.yml` |
| `.placeholder/ssh_key` | Delete | No longer needed; SSH key mount is conditional in override |
| `project-creds.json` | Untrack | `git rm --cached`; auto-migrated to `configurations.yml` on first run |
| `README.md` | Modify | Update prerequisites, volume map, build instructions, git credentials section, add mounts docs |

---

## Task 1: Update .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add new gitignore entries**

Open `.gitignore` and append:

```
configurations.yml
docker-compose.override.yml
```

Current content is:
```
.env
project-creds.json
```

Final content:
```
.env
project-creds.json
configurations.yml
docker-compose.override.yml
```

- [ ] **Step 2: Commit**

```bash
git -C ~/.claude-sandbox add .gitignore
git -C ~/.claude-sandbox commit -m "chore: gitignore configurations.yml and docker-compose.override.yml"
```

---

## Task 2: Rewrite `claude-sandbox.fish` + Simplify `docker-compose.yml`

These two files are tightly coupled — after this task the compose file has no env var slots, so the fish function must generate the override. They must be committed together.

**Files:**
- Modify: `functions/claude-sandbox.fish`
- Modify: `docker-compose.yml`

- [ ] **Step 1: Write the new fish function**

Replace the entire contents of `functions/claude-sandbox.fish` with:

```fish
function _sandbox_config_file
    echo $HOME/.claude-sandbox/configurations.yml
end

function _sandbox_config_read_creds_type
    # Returns "ssh", "none", or empty string if no entry exists
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.[$p].credentials.type // empty' $f 2>/dev/null
end

function _sandbox_config_read_creds_key
    # Returns keyPath or empty string
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.[$p].credentials.keyPath // empty' $f 2>/dev/null
end

function _sandbox_config_write_creds_ssh
    # Usage: _sandbox_config_write_creds_ssh <project_path> <key_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg k $argv[2] \
        '.[$p].credentials = {"type": "ssh", "keyPath": $k}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_write_creds_none
    # Usage: _sandbox_config_write_creds_none <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] \
        '.[$p].credentials = {"type": "none"}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_delete
    # Usage: _sandbox_config_delete <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] 'del(.[$p])' $f > $tmp
    and mv $tmp $f
end

function _sandbox_mounts_list
    # Usage: _sandbox_mounts_list <project_path>
    # Prints each mount spec on its own line; prints nothing if no mounts configured
    set -l f (_sandbox_config_file)
    test -f $f; or return
    yq -r --arg p $argv[1] '.[$p].mounts // [] | .[]' $f 2>/dev/null
end

function _sandbox_mounts_add
    # Usage: _sandbox_mounts_add <project_path> <mount_spec>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.[$p].mounts = ((.[$p].mounts // []) + [$m])' $f > $tmp
    and mv $tmp $f
end

function _sandbox_mounts_remove
    # Usage: _sandbox_mounts_remove <project_path> <mount_spec>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.[$p].mounts = [(.[$p].mounts // [])[] | select(. != $m)]' $f > $tmp
    and mv $tmp $f
end

function _sandbox_mounts_clear
    # Usage: _sandbox_mounts_clear <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] 'del(.[$p].mounts)' $f > $tmp
    and mv $tmp $f
end

function _sandbox_expand_path
    # Expand leading ~ to $HOME in a path read from user input
    string replace -r '^~/' $HOME/ $argv[1]
end

function _sandbox_copy_pubkey
    # Usage: _sandbox_copy_pubkey <pubkey_file_path>
    if uname -r | grep -qi microsoft
        cat $argv[1] | clip.exe
        and echo "Public key copied to clipboard."
    else
        echo "Note: clipboard not available. Public key:"
        cat $argv[1]
    end
end

function _sandbox_migrate_from_json
    # Auto-migrate project-creds.json → configurations.yml on first run after update
    set -l old_f $HOME/.claude-sandbox/project-creds.json
    set -l new_f (_sandbox_config_file)
    test -f $old_f; or return
    test -f $new_f; and return
    echo "Migrating project-creds.json to configurations.yml..."
    set -l tmp (mktemp)
    jq 'to_entries | map({key: .key, value: {credentials: .value}}) | from_entries' $old_f \
        | yq -y . > $tmp
    and mv $tmp $new_f
    and rm $old_f
    and echo "Migration complete."
end

function _sandbox_generate_override
    # Usage: _sandbox_generate_override <project_path> <project_name>
    # Writes ~/.claude-sandbox/docker-compose.override.yml
    set -l project_path $argv[1]
    set -l project_name $argv[2]
    set -l sandbox_dir $HOME/.claude-sandbox
    set -l out $sandbox_dir/docker-compose.override.yml

    set -l volumes \
        "      - $project_path:/workspace/$project_name" \
        "      - $sandbox_dir/.gitconfig:/home/claude/.gitconfig:ro"

    set -l creds_type (_sandbox_config_read_creds_type $project_path)
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_config_read_creds_key $project_path)
        set volumes $volumes "      - $key_path:/home/claude/.ssh/repo_key:ro"
    end

    for m in (_sandbox_mounts_list $project_path)
        set volumes $volumes "      - $m"
    end

    printf 'services:\n  claude-sandbox:\n    working_dir: /workspace/%s\n    volumes:\n' \
        $project_name > $out
    for vol in $volumes
        printf '%s\n' $vol >> $out
    end
end

function _sandbox_creds_wizard
    # Usage: _sandbox_creds_wizard <project_path> <project_name>
    set -l project_path $argv[1]
    set -l project_name $argv[2]

    echo ""
    echo "No SSH credentials configured for \"$project_path\"."
    echo ""
    echo "  1. Generate a new deploy key"
    echo "  2. Use an existing key"
    echo "  3. Skip (no git credentials)"
    echo ""
    read -P "Choice: " choice

    switch $choice
        case 1
            set -l default_path $HOME/.ssh/id_ed25519_$project_name
            read -P "Key path [$default_path]: " key_path
            if test -z "$key_path"
                set key_path $default_path
            else
                set key_path (_sandbox_expand_path $key_path)
            end

            ssh-keygen -t ed25519 -f $key_path -C "$project_name deploy key" -N ""
            or return 1

            echo ""
            echo "Key generated at $key_path"
            _sandbox_copy_pubkey "$key_path.pub"
            echo ""
            echo "GitHub : repo Settings → Deploy keys → Add deploy key  (enable \"Allow write access\" if needed)"
            echo "GitLab : repo Settings → Repository → Deploy keys"
            echo ""
            read -P "Press Enter when done to launch the sandbox..." _dummy

            _sandbox_config_write_creds_ssh $project_path $key_path

        case 2
            read -P "SSH key path: " key_path
            set key_path (_sandbox_expand_path $key_path)
            if not test -f $key_path
                echo "Error: key file not found: $key_path"
                return 1
            end
            _sandbox_config_write_creds_ssh $project_path $key_path

        case 3
            _sandbox_config_write_creds_none $project_path

        case '*'
            echo "Error: invalid choice '$choice'"
            return 1
    end
end

function claude-sandbox
    set -l PROJECT_PATH (pwd)
    set -l PROJECT_NAME (basename $PROJECT_PATH)
    set -l SANDBOX_DIR $HOME/.claude-sandbox

    # --- creds subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = creds
        set -l action $argv[2]
        switch $action
            case set
                if test (count $argv) -ge 3
                    set -l key_path (_sandbox_expand_path $argv[3])
                    if not test -f $key_path
                        echo "Error: key file not found: $key_path"
                        return 1
                    end
                    _sandbox_config_write_creds_ssh $PROJECT_PATH $key_path
                    echo "Saved SSH key for $PROJECT_PATH"
                else
                    _sandbox_creds_wizard $PROJECT_PATH $PROJECT_NAME
                end
            case show
                set -l t (_sandbox_config_read_creds_type $PROJECT_PATH)
                if test -z "$t"
                    echo "No credentials configured for $PROJECT_PATH"
                else if test "$t" = ssh
                    echo "type: ssh"
                    echo "keyPath: "(_sandbox_config_read_creds_key $PROJECT_PATH)
                else
                    echo "type: none (no git credentials)"
                end
            case clear
                _sandbox_config_delete $PROJECT_PATH
                echo "Cleared credentials for $PROJECT_PATH (will prompt on next launch)"
            case list
                set -l f (_sandbox_config_file)
                if not test -f $f
                    echo "No credentials configured."
                    return
                end
                yq -r 'to_entries[] | "\(.key)\n  type: \(.value.credentials.type)" + (if .value.credentials.keyPath then "\n  keyPath: \(.value.credentials.keyPath)" else "" end)' $f
            case '*'
                echo "Usage: claude-sandbox creds {set [key-path]|show|clear|list}"
                return 1
        end
        return
    end

    # --- mounts subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = mounts
        set -l action $argv[2]
        switch $action
            case add
                if test (count $argv) -lt 3
                    echo "Usage: claude-sandbox mounts add <source>:<target>[:<options>]"
                    return 1
                end
                _sandbox_mounts_add $PROJECT_PATH $argv[3]
                echo "Added mount for $PROJECT_PATH: $argv[3]"
            case remove
                if test (count $argv) -lt 3
                    echo "Usage: claude-sandbox mounts remove <source>:<target>[:<options>]"
                    return 1
                end
                _sandbox_mounts_remove $PROJECT_PATH $argv[3]
                echo "Removed mount for $PROJECT_PATH: $argv[3]"
            case list
                set -l mounts (_sandbox_mounts_list $PROJECT_PATH)
                if test (count $mounts) -eq 0
                    echo "No extra mounts configured for $PROJECT_PATH"
                else
                    for m in $mounts
                        echo $m
                    end
                end
            case clear
                _sandbox_mounts_clear $PROJECT_PATH
                echo "Cleared all mounts for $PROJECT_PATH"
            case '*'
                echo "Usage: claude-sandbox mounts {add <spec>|remove <spec>|list|clear}"
                return 1
        end
        return
    end

    # --- launch flow ---
    if not docker info > /dev/null 2>&1
        echo "Error: Docker is not running. Please start Docker Desktop first."
        return 1
    end

    # Auto-migrate from legacy project-creds.json
    _sandbox_migrate_from_json

    # Resolve credentials for this project
    set -l creds_type (_sandbox_config_read_creds_type $PROJECT_PATH)
    if test -z "$creds_type"
        _sandbox_creds_wizard $PROJECT_PATH $PROJECT_NAME
        or return 1
        set creds_type (_sandbox_config_read_creds_type $PROJECT_PATH)
    end

    # Verify SSH key exists if configured
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_config_read_creds_key $PROJECT_PATH)
        if not test -f $key_path
            echo "Error: SSH key not found: $key_path"
            echo "Run 'claude-sandbox creds set' to reconfigure."
            return 1
        end
    end

    echo "Starting sandbox for $PROJECT_NAME..."

    # Generate docker-compose.override.yml for this project
    _sandbox_generate_override $PROJECT_PATH $PROJECT_NAME

    if not docker compose -f $SANDBOX_DIR/docker-compose.yml up -d --force-recreate
        echo "Error: Failed to start the sandbox container."
        return 1
    end

    set container_json "{\"containerName\":\"/claude-sandbox\"}"
    set encoded (printf '%s' $container_json | xxd -p | tr -d '\n')

    code --folder-uri "vscode-remote://attached-container+$encoded/workspace/$PROJECT_NAME"
end
```

- [ ] **Step 2: Verify fish syntax is valid**

```bash
fish -n ~/.claude-sandbox/functions/claude-sandbox.fish
```

Expected: no output (silent = valid).

- [ ] **Step 3: Write the new static docker-compose.yml**

Replace the entire contents of `docker-compose.yml` with:

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

- [ ] **Step 4: Verify compose file is valid**

```bash
docker compose -f ~/.claude-sandbox/docker-compose.yml config --quiet
```

Expected: no output (silent = valid).

- [ ] **Step 5: Verify override generation works end-to-end**

Source the updated fish function, then test override generation for an existing project that has credentials configured:

```bash
source ~/.claude-sandbox/functions/claude-sandbox.fish
cd ~/mattle-fun/godew-valley  # or any project with credentials in project-creds.json
_sandbox_generate_override (pwd) (basename (pwd))
cat ~/.claude-sandbox/docker-compose.override.yml
```

Expected output (paths will vary):
```yaml
services:
  claude-sandbox:
    working_dir: /workspace/godew-valley
    volumes:
      - /home/lhvubtqn/mattle-fun/godew-valley:/workspace/godew-valley
      - /home/lhvubtqn/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
      - /home/lhvubtqn/.ssh/id_ed25519_godew-valley:/home/claude/.ssh/repo_key:ro
```

Note: migration will run automatically the first time `_sandbox_migrate_from_json` is called. If `project-creds.json` exists it will be converted to `configurations.yml` and deleted.

- [ ] **Step 6: Verify creds subcommand still works**

```bash
cd ~/mattle-fun/godew-valley
claude-sandbox creds show
```

Expected:
```
type: ssh
keyPath: /home/lhvubtqn/.ssh/id_ed25519_godew-valley
```

- [ ] **Step 7: Verify mounts subcommand**

```bash
cd ~/mattle-fun/godew-valley
claude-sandbox mounts list
```

Expected: `No extra mounts configured for /home/lhvubtqn/mattle-fun/godew-valley`

```bash
claude-sandbox mounts add /tmp/test-resource:/workspace/test-resource:ro
claude-sandbox mounts list
```

Expected: `/tmp/test-resource:/workspace/test-resource:ro`

```bash
claude-sandbox mounts remove /tmp/test-resource:/workspace/test-resource:ro
claude-sandbox mounts list
```

Expected: `No extra mounts configured for ...`

- [ ] **Step 8: Copy updated fish function to user functions directory**

```bash
cp ~/.claude-sandbox/functions/claude-sandbox.fish ~/.config/fish/functions/claude-sandbox.fish
```

- [ ] **Step 9: Commit both files together**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish docker-compose.yml
git -C ~/.claude-sandbox commit -m "feat: per-project mounts via configurations.yml and override file"
```

---

## Task 3: Simplify Makefile

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Remove env vars from build targets**

`docker-compose.yml` no longer uses `${PROJECT_PATH}` or `${PROJECT_NAME}`, so the build targets no longer need them.

Replace the `build` and `build-no-cache` targets:

```makefile
build:
	$(COMPOSE) build

build-no-cache:
	$(COMPOSE) build --no-cache
```

The full updated Makefile:

```makefile
COMPOSE = docker compose -f $(HOME)/.claude-sandbox/docker-compose.yml

.PHONY: build build-no-cache down shell logs clean

build:
	$(COMPOSE) build

build-no-cache:
	$(COMPOSE) build --no-cache

down:
	$(COMPOSE) down

shell:
	docker exec -it claude-sandbox bash

logs:
	docker logs -f claude-sandbox

clean:
	$(COMPOSE) down -v
```

- [ ] **Step 2: Verify Makefile parses correctly**

```bash
make -C ~/.claude-sandbox -n build
```

Expected: `docker compose -f /home/lhvubtqn/.claude-sandbox/docker-compose.yml build`

- [ ] **Step 3: Commit**

```bash
git -C ~/.claude-sandbox add Makefile
git -C ~/.claude-sandbox commit -m "chore: remove PROJECT_PATH/PROJECT_NAME env vars from Makefile build targets"
```

---

## Task 4: Update `entrypoint.sh` — `.claude.json` symlink

**Files:**
- Modify: `entrypoint.sh`

- [ ] **Step 1: Add .claude.json persistence to entrypoint**

Add two lines before `exec "$@"`. The file currently ends with:

```sh
    chmod 600 /home/claude/.ssh/config
fi
exec "$@"
```

Updated file:

```sh
#!/bin/bash
set -euo pipefail
if [ -s /home/claude/.ssh/repo_key ]; then
    chmod 600 /home/claude/.ssh/repo_key 2>/dev/null || true
    cat > /home/claude/.ssh/config << 'EOF'
Host *
  IdentityFile /home/claude/.ssh/repo_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
    chmod 600 /home/claude/.ssh/config
fi
[ -f /home/claude/.claude/.claude.json ] || echo '{}' > /home/claude/.claude/.claude.json
ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json
exec "$@"
```

- [ ] **Step 2: Commit**

```bash
git -C ~/.claude-sandbox add entrypoint.sh
git -C ~/.claude-sandbox commit -m "feat: persist .claude.json in claude-config volume via symlink"
```

---

## Task 5: Remove Old Files

**Files:**
- Delete: `.placeholder/ssh_key`
- Untrack: `project-creds.json` (file may already be gone after auto-migration)

- [ ] **Step 1: Remove .placeholder/ from git and disk**

```bash
git -C ~/.claude-sandbox rm -r .placeholder/
```

Expected: `rm '.placeholder/ssh_key'`

- [ ] **Step 2: Remove project-creds.json from git tracking**

If the file still exists on disk (migration not yet run):
```bash
git -C ~/.claude-sandbox rm --cached project-creds.json 2>/dev/null || true
```

If the file is already gone (migration ran in Task 2 verification), skip — it's already untracked since it's in `.gitignore`.

- [ ] **Step 3: Commit**

```bash
git -C ~/.claude-sandbox commit -m "chore: remove .placeholder/ dir and untrack project-creds.json"
```

---

## Task 6: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update Prerequisites section**

Replace the `jq` line and add `yq`:

```markdown
- `xxd` (`sudo apt install xxd` if missing)
- `yq` (`sudo apt install yq` if missing — Ubuntu package, kislyuk's implementation)
```

Remove the `jq` prerequisite line entirely (no longer needed).

- [ ] **Step 2: Update Setup section — Step 4 (build)**

Old:
```bash
PROJECT_PATH=/tmp PROJECT_NAME=build docker compose -f ~/.claude-sandbox/docker-compose.yml build
```

New:
```bash
docker compose -f ~/.claude-sandbox/docker-compose.yml build
```

- [ ] **Step 3: Update Volume map table**

Remove the `~/.claude.json (bind)` row. Add a note to the `claude-config` row:

| Volume | Path in container | Purpose |
|---|---|---|
| `claude-config` | `/home/claude/.claude` | Claude Code auth, config, session, and `.claude.json` (symlinked from `/home/claude/.claude.json`) |

Remove these rows:
- `~/.claude.json (bind)` row
- `${SANDBOX_SSH_KEY_PATH} (bind)` row (SSH key is now in the generated override, not static compose)

Add a note below the table:
> The SSH deploy key is bind-mounted via the generated `docker-compose.override.yml` when configured. See [Git credentials](#git-credentials).

- [ ] **Step 4: Update Git credentials section**

Replace references to `project-creds.json` with `configurations.yml`. Add the new `mounts` subcommand documentation after the `creds` subcommand docs:

```markdown
Mount additional host resources into the container on a per-project basis:

```bash
claude-sandbox mounts add /opt/godot:/usr/local/bin/godot:ro   # bind a host path into the container
claude-sandbox mounts list                                       # show configured mounts for current project
claude-sandbox mounts remove /opt/godot:/usr/local/bin/godot:ro # remove a mount
claude-sandbox mounts clear                                      # remove all mounts for current project
```

Mount specs use Docker bind-mount syntax: `<host-path>:<container-path>[:<options>]`. Options include `ro` (read-only).
```

- [ ] **Step 5: Commit**

```bash
git -C ~/.claude-sandbox add README.md
git -C ~/.claude-sandbox commit -m "docs: update README for yq prereq, static compose build, mounts subcommand"
```

---

## Task 7: Rebuild Container and Migrate `.claude.json`

This task runs after the container image is rebuilt with the new `entrypoint.sh`.

- [ ] **Step 1: Rebuild the container image**

```bash
make -C ~/.claude-sandbox build
```

Expected: Docker build completes successfully. This updates the image with the new entrypoint.

- [ ] **Step 2: Copy `.claude.json` into the claude-config volume**

The existing `~/mattle-fun/godew-valley` project (or any project) must be launched once first to start the container, then the migration can run. Run from that project:

```bash
cd ~/mattle-fun/godew-valley
claude-sandbox
```

This will start the container with the new entrypoint. The entrypoint creates `{}` as the initial `.claude.json` inside the volume.

- [ ] **Step 3: Copy existing host `.claude.json` into the volume**

```bash
docker cp ~/.claude.json claude-sandbox:/home/claude/.claude/.claude.json
```

Expected: no output (silent = success).

- [ ] **Step 4: Restart the container so the symlink picks up the new file**

```bash
docker restart claude-sandbox
```

- [ ] **Step 5: Verify Claude Code session is preserved**

Open a terminal inside the container and run:

```bash
docker exec -it claude-sandbox bash -c "cat /home/claude/.claude.json | head -5"
```

Expected: the file contains your account data (not `{}`).

```bash
docker exec -it claude-sandbox bash -c "ls -la /home/claude/.claude.json"
```

Expected: shows a symlink pointing to `/home/claude/.claude/.claude.json`.

- [ ] **Step 6: Verify Claude Code recognizes the session**

Inside VS Code attached to the container, run `claude` — it should not prompt for login.
