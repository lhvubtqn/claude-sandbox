# Per-Repo Git Credentials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-project SSH credential injection to claude-sandbox, with an interactive setup wizard on first launch and `creds` subcommands for day-to-day management.

**Architecture:** Three layers — (1) a Docker entrypoint writes `~/.ssh/config` inside the container when a key is bind-mounted; (2) `docker-compose.yml` binds the key at a fixed container path using `$SANDBOX_SSH_KEY_PATH` with an empty-file fallback; (3) the fish function reads/writes `~/.claude-sandbox/project-creds.json` via `jq` and runs an interactive wizard on the first launch of any project.

**Tech Stack:** Fish shell, jq, Docker Compose, ssh-keygen, clip.exe (WSL2 clipboard)

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `~/.claude-sandbox/entrypoint.sh` | Create | Writes `~/.ssh/config` inside container when key is mounted |
| `~/.claude-sandbox/Dockerfile` | Modify | COPY entrypoint.sh, add ENTRYPOINT directive |
| `~/.claude-sandbox/docker-compose.yml` | Modify | Relative `.gitconfig` path, add SSH key volume |
| `~/.claude-sandbox/.ssh_placeholder` | Create | Empty file — fallback volume target when no key configured |
| `~/.claude-sandbox/.gitconfig` | Create | Copy of host gitconfig, managed independently |
| `~/.claude-sandbox/functions/claude-sandbox.fish` | Rewrite | Credential helpers, wizard, creds subcommands, updated launch flow |

---

## Task 1: entrypoint.sh + Dockerfile

**Files:**
- Create: `~/.claude-sandbox/entrypoint.sh`
- Modify: `~/.claude-sandbox/Dockerfile`

- [ ] **Step 1: Create entrypoint.sh**

```bash
#!/bin/bash
if [ -s /home/claude/.ssh/repo_key ]; then
    mkdir -p /home/claude/.ssh
    chmod 700 /home/claude/.ssh
    cat > /home/claude/.ssh/config << 'EOF'
Host *
  IdentityFile /home/claude/.ssh/repo_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
    chmod 600 /home/claude/.ssh/config
fi
exec "$@"
```

Save to `~/.claude-sandbox/entrypoint.sh`.

- [ ] **Step 2: Update Dockerfile**

Add these two lines immediately before the final `WORKDIR /workspace` line:

```dockerfile
COPY --chown=claude:claude entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

The full tail of the Dockerfile becomes:

```dockerfile
# Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

COPY --chown=claude:claude entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /workspace
```

- [ ] **Step 3: Build the image**

```bash
cd ~/.claude-sandbox
make build
```

Expected: build completes with no errors.

- [ ] **Step 4: Test — no key mounted (placeholder)**

```bash
touch ~/.claude-sandbox/.ssh_placeholder
docker run --rm \
  -v ~/.claude-sandbox/.ssh_placeholder:/home/claude/.ssh/repo_key:ro \
  claude-sandbox bash -c "ls /home/claude/.ssh/config 2>&1"
```

Expected output: `ls: cannot access '/home/claude/.ssh/config': No such file or directory`

- [ ] **Step 5: Test — real key mounted**

```bash
# Use any existing key on your machine for this test
docker run --rm \
  -v ~/.ssh/id_ed25519:/home/claude/.ssh/repo_key:ro \
  claude-sandbox bash -c "cat /home/claude/.ssh/config"
```

Expected output:
```
Host *
  IdentityFile /home/claude/.ssh/repo_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
```

- [ ] **Step 6: Commit**

```bash
cd ~/.claude-sandbox
git add entrypoint.sh Dockerfile
git commit -m "feat: add entrypoint to inject ssh config when key is mounted"
```

---

## Task 2: docker-compose.yml + placeholder files

**Files:**
- Modify: `~/.claude-sandbox/docker-compose.yml`
- Create: `~/.claude-sandbox/.ssh_placeholder`
- Create: `~/.claude-sandbox/.gitconfig`

- [ ] **Step 1: Create .ssh_placeholder**

```bash
touch ~/.claude-sandbox/.ssh_placeholder
```

- [ ] **Step 2: Copy .gitconfig from host**

```bash
cp ~/.gitconfig ~/.claude-sandbox/.gitconfig
```

- [ ] **Step 3: Update docker-compose.yml**

Replace the entire `volumes:` block under `claude-sandbox:` service with:

```yaml
    volumes:
      - ${PROJECT_PATH:-/tmp}:/workspace/${PROJECT_NAME:-placeholder}
      - claude-config:/home/claude/.claude
      - ${HOME}/.claude.json:/home/claude/.claude.json
      - .gitconfig:/home/claude/.gitconfig:ro
      - ${SANDBOX_SSH_KEY_PATH:-.ssh_placeholder}:/home/claude/.ssh/repo_key:ro
      - cargo-registry:/home/claude/.cargo/registry
      - cargo-git:/home/claude/.cargo/git
      - rustup-downloads:/home/claude/.rustup/downloads
      - npm-cache:/home/claude/.npm
      - solana-config:/home/claude/.config/solana
      - vscode-server:/home/claude/.vscode-server
```

Key changes: `${HOME}/.gitconfig` → `.gitconfig`, new SSH key volume line added.

- [ ] **Step 4: Verify compose config is valid**

```bash
cd ~/.claude-sandbox
PROJECT_PATH=/tmp PROJECT_NAME=test docker compose config
```

Expected: full rendered YAML with no errors. Confirm the `.gitconfig` volume shows the absolute path to `~/.claude-sandbox/.gitconfig` and `.ssh_placeholder` shows up for the SSH key volume.

- [ ] **Step 5: Rebuild image (needed because compose file changed)**

```bash
make build
```

Expected: build completes with no errors.

- [ ] **Step 6: Commit**

```bash
cd ~/.claude-sandbox
git add .ssh_placeholder .gitconfig docker-compose.yml
git commit -m "feat: add ssh key volume and relative gitconfig mount to compose"
```

---

## Task 3: Fish credential helper functions

**Files:**
- Modify: `~/.claude-sandbox/functions/claude-sandbox.fish`

Replace the entire file contents. All helper functions are defined before `claude-sandbox` so they are available when the file is sourced.

- [ ] **Step 1: Add credential helper functions**

Replace the top of `claude-sandbox.fish` (before the existing `function claude-sandbox` line) with:

```fish
function _sandbox_creds_file
    echo $HOME/.claude-sandbox/project-creds.json
end

function _sandbox_creds_read_type
    # Returns "ssh", "none", or empty string if no entry exists
    set -l f (_sandbox_creds_file)
    test -f $f; or begin; echo ""; return; end
    jq -r --arg p $argv[1] '.[$p].type // empty' $f
end

function _sandbox_creds_read_key
    # Returns keyPath or empty string
    set -l f (_sandbox_creds_file)
    test -f $f; or begin; echo ""; return; end
    jq -r --arg p $argv[1] '.[$p].keyPath // empty' $f
end

function _sandbox_creds_write_ssh
    # Usage: _sandbox_creds_write_ssh <project_path> <key_path>
    set -l f (_sandbox_creds_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    jq --arg p $argv[1] --arg k $argv[2] \
        '.[$p] = {"type": "ssh", "keyPath": $k}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_creds_write_none
    # Usage: _sandbox_creds_write_none <project_path>
    set -l f (_sandbox_creds_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    jq --arg p $argv[1] '.[$p] = {"type": "none"}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_creds_delete
    # Usage: _sandbox_creds_delete <project_path>
    set -l f (_sandbox_creds_file)
    test -f $f; or return
    set -l tmp (mktemp)
    jq --arg p $argv[1] 'del(.[$p])' $f > $tmp
    and mv $tmp $f
end

function _sandbox_expand_path
    # Expand leading ~ to $HOME in a path read from user input
    string replace -r '^~/' $HOME/ $argv[1]
end

function _sandbox_copy_pubkey
    # Usage: _sandbox_copy_pubkey <pubkey_file_path>
    # Copies content to clipboard on WSL2; falls back to printing content
    if uname -r | grep -qi microsoft
        cat $argv[1] | clip.exe
        and echo "Public key copied to clipboard."
    else
        echo "Note: clipboard not available. Public key:"
        cat $argv[1]
    end
end
```

- [ ] **Step 2: Source the file and test helpers manually**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish

# Test write and read
_sandbox_creds_write_ssh /tmp/testproject ~/.ssh/id_ed25519
_sandbox_creds_read_type /tmp/testproject   # → "ssh"
_sandbox_creds_read_key  /tmp/testproject   # → "/home/<you>/.ssh/id_ed25519"

# Test none
_sandbox_creds_write_none /tmp/other
_sandbox_creds_read_type /tmp/other         # → "none"

# Test delete
_sandbox_creds_delete /tmp/testproject
_sandbox_creds_read_type /tmp/testproject   # → (empty)

# Test expand path
_sandbox_expand_path "~/.ssh/mykey"         # → "/home/<you>/.ssh/mykey"

# Cleanup
rm -f ~/.claude-sandbox/project-creds.json
```

- [ ] **Step 3: Commit**

```bash
cd ~/.claude-sandbox
git add functions/claude-sandbox.fish
git commit -m "feat: add fish credential helper functions"
```

---

## Task 4: Credential setup wizard

**Files:**
- Modify: `~/.claude-sandbox/functions/claude-sandbox.fish`

**Prerequisite:** Task 3 must be complete — `_sandbox_copy_pubkey` and `_sandbox_creds_write_ssh`/`_sandbox_creds_write_none` are called by the wizard.

- [ ] **Step 1: Add the wizard function**

Add this function after the `_sandbox_copy_pubkey` function and before `function claude-sandbox`:

```fish
function _sandbox_creds_wizard
    # Usage: _sandbox_creds_wizard <project_path> <project_name>
    # Runs the interactive credential setup wizard.
    # On success, writes entry to project-creds.json and returns 0.
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

            _sandbox_creds_write_ssh $project_path $key_path

        case 2
            read -P "SSH key path: " key_path
            set key_path (_sandbox_expand_path $key_path)
            if not test -f $key_path
                echo "Error: key file not found: $key_path"
                return 1
            end
            _sandbox_creds_write_ssh $project_path $key_path

        case 3
            _sandbox_creds_write_none $project_path

        case '*'
            echo "Error: invalid choice '$choice'"
            return 1
    end
end
```

- [ ] **Step 2: Test the wizard — option 1 (generate)**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
_sandbox_creds_wizard /tmp/wizard-test wizard-test
# Choose 1, accept default path, check key is created, paste deploy key, press Enter
# Then verify:
_sandbox_creds_read_type /tmp/wizard-test    # → "ssh"
_sandbox_creds_read_key  /tmp/wizard-test    # → path to generated key
```

- [ ] **Step 3: Test the wizard — option 2 (existing key)**

```fish
rm ~/.claude-sandbox/project-creds.json
_sandbox_creds_wizard /tmp/wizard-test wizard-test
# Choose 2, enter path to an existing key
_sandbox_creds_read_type /tmp/wizard-test    # → "ssh"
```

- [ ] **Step 4: Test the wizard — option 3 (skip)**

```fish
rm ~/.claude-sandbox/project-creds.json
_sandbox_creds_wizard /tmp/wizard-test wizard-test
# Choose 3
_sandbox_creds_read_type /tmp/wizard-test    # → "none"
```

- [ ] **Step 5: Clean up test state and commit**

```bash
rm -f ~/.claude-sandbox/project-creds.json
cd ~/.claude-sandbox
git add functions/claude-sandbox.fish
git commit -m "feat: add interactive credential setup wizard"
```

---

## Task 5: Main launch flow + creds subcommands

**Files:**
- Modify: `~/.claude-sandbox/functions/claude-sandbox.fish`

- [ ] **Step 1: Replace the `claude-sandbox` function body**

Replace the entire `function claude-sandbox ... end` block with:

```fish
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
                    _sandbox_creds_write_ssh $PROJECT_PATH $key_path
                    echo "Saved SSH key for $PROJECT_PATH"
                else
                    _sandbox_creds_wizard $PROJECT_PATH $PROJECT_NAME
                end
            case show
                set -l t (_sandbox_creds_read_type $PROJECT_PATH)
                if test -z "$t"
                    echo "No credentials configured for $PROJECT_PATH"
                else if test "$t" = ssh
                    echo "type: ssh"
                    echo "keyPath: "(_sandbox_creds_read_key $PROJECT_PATH)
                else
                    echo "type: none (no git credentials)"
                end
            case clear
                _sandbox_creds_delete $PROJECT_PATH
                echo "Cleared credentials for $PROJECT_PATH (will prompt on next launch)"
            case list
                set -l f (_sandbox_creds_file)
                if not test -f $f
                    echo "No credentials configured."
                    return
                end
                jq -r 'to_entries[] | "\(.key)\n  type: \(.value.type)" + (if .value.keyPath then "\n  keyPath: \(.value.keyPath)" else "" end)' $f
            case '*'
                echo "Usage: claude-sandbox creds {set [key-path]|show|clear|list}"
                return 1
        end
        return
    end

    # --- launch flow ---
    if not docker info > /dev/null 2>&1
        echo "Error: Docker is not running. Please start Docker Desktop first."
        return 1
    end

    # Resolve credentials for this project
    set -l creds_type (_sandbox_creds_read_type $PROJECT_PATH)
    if test -z "$creds_type"
        _sandbox_creds_wizard $PROJECT_PATH $PROJECT_NAME
        or return 1
        set creds_type (_sandbox_creds_read_type $PROJECT_PATH)
    end

    # Clear any previously exported value before conditionally setting
    set -e SANDBOX_SSH_KEY_PATH
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_creds_read_key $PROJECT_PATH)
        if not test -f $key_path
            echo "Error: SSH key not found: $key_path"
            echo "Run 'claude-sandbox creds set' to reconfigure."
            return 1
        end
        set -x SANDBOX_SSH_KEY_PATH $key_path
    end

    echo "Starting sandbox for $PROJECT_NAME..."

    set -x PROJECT_PATH $PROJECT_PATH
    set -x PROJECT_NAME $PROJECT_NAME

    if not docker compose -f $SANDBOX_DIR/docker-compose.yml up -d --force-recreate
        echo "Error: Failed to start the sandbox container."
        return 1
    end

    set container_json "{\"containerName\":\"/claude-sandbox\"}"
    set encoded (printf '%s' $container_json | xxd -p | tr -d '\n')

    code --folder-uri "vscode-remote://attached-container+$encoded/workspace/$PROJECT_NAME"
end
```

- [ ] **Step 2: Source the file and test `creds show` (no entry)**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
cd /tmp
claude-sandbox creds show
```

Expected: `No credentials configured for /tmp`

- [ ] **Step 3: Test `creds set <path>`**

```fish
claude-sandbox creds set ~/.ssh/id_ed25519   # use any existing key
claude-sandbox creds show
```

Expected:
```
type: ssh
keyPath: /home/<you>/.ssh/id_ed25519
```

- [ ] **Step 4: Test `creds list`**

```fish
cd /tmp
claude-sandbox creds list
```

Expected: shows `/tmp` with type and keyPath.

- [ ] **Step 5: Test `creds clear`**

```fish
claude-sandbox creds clear
claude-sandbox creds show
```

Expected:
```
Cleared credentials for /tmp (will prompt on next launch)
No credentials configured for /tmp
```

- [ ] **Step 6: End-to-end launch test — ssh type**

```fish
# Set a real key for the current sandbox project
cd ~/your-project
claude-sandbox creds set ~/.ssh/id_ed25519_yourrepo

# Launch (no wizard prompt expected)
claude-sandbox
```

After container starts:
```bash
docker exec claude-sandbox cat /home/claude/.ssh/config
```

Expected: SSH config present with the repo key.

- [ ] **Step 7: End-to-end launch test — none type**

```fish
cd ~/another-project
# Run claude-sandbox, choose option 3 (skip) in the wizard
claude-sandbox
```

After container starts:
```bash
docker exec claude-sandbox ls /home/claude/.ssh/config 2>&1
```

Expected: `No such file or directory`

- [ ] **Step 8: Clean up test state and commit**

```bash
rm -f ~/.claude-sandbox/project-creds.json
cd ~/.claude-sandbox
git add functions/claude-sandbox.fish
git commit -m "feat: wire credential wizard and creds subcommands into claude-sandbox"
```
