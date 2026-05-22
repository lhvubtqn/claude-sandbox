# Git Auth Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SSH-only credentials wizard with a unified SSH + PAT flow, add per-project git identity injection, and remove the host `~/.gitconfig` bind mount.

**Architecture:** All git auth config is stored per-project under `projects[$path].git_auth` in `configurations.yml`. On container start, env vars (`SANDBOX_GIT_AUTH_TYPE`, `SANDBOX_GIT_NAME`, `SANDBOX_GIT_EMAIL`, `SANDBOX_GIT_PREFER_SSH`) and a single unified mount at `/home/claude/.gitcreds` carry credentials + identity into the container; `entrypoint.sh` writes `.gitconfig` and SSH/credential-helper config from those inputs.

**Tech Stack:** fish shell, bash, yq (jq-style YAML), Docker

---

## File Map

| File | Change |
|---|---|
| `configurations.yml` | Remove `${HOME}/.gitconfig:/home/claude/.gitconfig:ro` from global volumes |
| `entrypoint.sh` | Replace deploy-key block with unified `SANDBOX_GIT_AUTH_TYPE` handler |
| `functions/claude-sandbox.fish` | Add `git_auth` helpers; rename old `creds` helpers; update `_sandbox_docker_run`; rewrite wizard; rename `creds` subcommand to `git-auth` |
| `completions/claude-sandbox.fish` | Replace `creds` with `git-auth` |

---

## Task 1: Remove `~/.gitconfig` bind mount from `configurations.yml`

**Files:**
- Modify: `configurations.yml`

- [ ] **Step 1: Remove the gitconfig volume line**

Open `configurations.yml`. The `global.container.volumes` list currently contains:
```yaml
      - ${HOME}/.gitconfig:/home/claude/.gitconfig:ro
```
Delete that line. Result:
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
      - ${WORKDIR}/skills:/home/claude/.claude/skills:ro
      - ${WORKDIR}/rules:/home/claude/.claude/rules:ro
```

- [ ] **Step 2: Verify no gitconfig reference remains**

```bash
grep gitconfig configurations.yml
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add configurations.yml
git commit -m "feat: remove host gitconfig bind mount"
```

---

## Task 2: Rewrite `entrypoint.sh`

**Files:**
- Modify: `entrypoint.sh`

- [ ] **Step 1: Replace the deploy-key block**

Current content of `entrypoint.sh`:
```bash
#!/bin/bash
set -euo pipefail
if [ -s /home/claude/.ssh/deploy_key ]; then
    cat > /home/claude/.ssh/config << 'EOF'
Host *
  IdentityFile /home/claude/.ssh/deploy_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
    chmod 600 /home/claude/.ssh/config
fi
[ -f /home/claude/.claude/.claude.json ] || echo '{}' > /home/claude/.claude/.claude.json
ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json
exec "$@"
```

Replace entirely with:
```bash
#!/bin/bash
set -euo pipefail

if [ "${SANDBOX_GIT_AUTH_TYPE:-}" = ssh ] && [ -f /home/claude/.gitcreds ]; then
    cat > /home/claude/.ssh/config << 'EOF'
Host *
  IdentityFile /home/claude/.gitcreds
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
    chmod 600 /home/claude/.ssh/config
fi

if [ "${SANDBOX_GIT_AUTH_TYPE:-}" = pat ] && [ -f /home/claude/.gitcreds ]; then
    TOKEN=$(cat /home/claude/.gitcreds)
    printf 'https://%s@github.com\n' "$TOKEN" > /home/claude/.git-credentials
    chmod 600 /home/claude/.git-credentials
    git config --global credential.helper "store --file /home/claude/.git-credentials"
fi

if [ -n "${SANDBOX_GIT_NAME:-}" ]; then
    git config --global user.name "$SANDBOX_GIT_NAME"
fi
if [ -n "${SANDBOX_GIT_EMAIL:-}" ]; then
    git config --global user.email "$SANDBOX_GIT_EMAIL"
fi
if [ "${SANDBOX_GIT_PREFER_SSH:-}" = 1 ]; then
    git config --global url."git@github.com:".insteadOf "https://github.com/"
fi

[ -f /home/claude/.claude/.claude.json ] || echo '{}' > /home/claude/.claude/.claude.json
ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json
exec "$@"
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n entrypoint.sh
```
Expected: no output (clean syntax).

- [ ] **Step 3: Commit**

```bash
git add entrypoint.sh
git commit -m "feat: replace deploy-key block with unified SANDBOX_GIT_AUTH_TYPE handler"
```

---

## Task 3: Add `git_auth` config helpers and remove old `creds` helpers

**Files:**
- Modify: `functions/claude-sandbox.fish`

The top of the file has these helper functions that need replacing:
- `_sandbox_config_read_creds_type` → remove
- `_sandbox_config_read_creds_key` → remove
- `_sandbox_config_write_creds_ssh` → remove
- `_sandbox_config_write_creds_none` → remove
- `_sandbox_config_delete` → update to use `git_auth`

Replace the four old `creds` helpers (lines roughly from `function _sandbox_config_read_creds_type` through the end of `function _sandbox_config_write_creds_none`) with the new set below, and update `_sandbox_config_delete`.

- [ ] **Step 1: Replace the four old creds helpers with seven new git_auth helpers**

Find and replace the block:
```fish
function _sandbox_config_read_creds_type
    # Returns "ssh", "none", or empty string if no entry exists
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].credentials.type // empty' $f 2>/dev/null
end

function _sandbox_config_read_creds_key
    # Returns keyPath or empty string
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].credentials.keyPath // empty' $f 2>/dev/null
end

function _sandbox_config_write_creds_ssh
    # Usage: _sandbox_config_write_creds_ssh <project_path> <key_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg k $argv[2] \
        '.projects[$p].credentials = {"type": "ssh", "keyPath": $k}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_write_creds_none
    # Usage: _sandbox_config_write_creds_none <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] \
        '.projects[$p].credentials = {"type": "none"}' $f > $tmp
    and mv $tmp $f
end
```

With:
```fish
function _sandbox_config_read_git_auth_type
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.type // empty' $f 2>/dev/null
end

function _sandbox_config_read_git_auth_path
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.path // empty' $f 2>/dev/null
end

function _sandbox_config_read_git_auth_prefer_ssh
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.prefer_ssh // empty' $f 2>/dev/null
end

function _sandbox_config_read_git_auth_identity_name
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.identity.name // empty' $f 2>/dev/null
end

function _sandbox_config_read_git_auth_identity_email
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.identity.email // empty' $f 2>/dev/null
end

function _sandbox_config_write_git_auth_ssh
    # Usage: _sandbox_config_write_git_auth_ssh <project_path> <key_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg k $argv[2] \
        '.projects[$p].git_auth = {"type": "ssh", "path": $k, "prefer_ssh": true}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_write_git_auth_pat
    # Usage: _sandbox_config_write_git_auth_pat <project_path> <token_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg t $argv[2] \
        '.projects[$p].git_auth = {"type": "pat", "path": $t}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_write_git_auth_none
    # Usage: _sandbox_config_write_git_auth_none <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] \
        '.projects[$p].git_auth = {"type": "none"}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_write_git_auth_identity
    # Usage: _sandbox_config_write_git_auth_identity <project_path> <name> <email>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg n $argv[2] --arg e $argv[3] \
        '.projects[$p].git_auth.identity = {"name": $n, "email": $e}' $f > $tmp
    and mv $tmp $f
end
```

- [ ] **Step 2: Update `_sandbox_config_delete` to use `git_auth`**

Find:
```fish
function _sandbox_config_delete
    # Usage: _sandbox_config_delete <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] 'del(.projects[$p].credentials)' $f > $tmp
    and mv $tmp $f
end
```

Replace with:
```fish
function _sandbox_config_delete
    # Usage: _sandbox_config_delete <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] 'del(.projects[$p].git_auth)' $f > $tmp
    and mv $tmp $f
end
```

- [ ] **Step 3: Verify yq write helper works**

```bash
echo '{}' | yq -y --arg p "/test/path" --arg k "~/.ssh/id_test" \
  '.projects[$p].git_auth = {"type": "ssh", "path": $k, "prefer_ssh": true}'
```
Expected output:
```yaml
projects:
  /test/path:
    git_auth:
      type: ssh
      path: ~/.ssh/id_test
      prefer_ssh: true
```

- [ ] **Step 4: Verify fish syntax**

```bash
fish -n functions/claude-sandbox.fish
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: add git_auth config helpers; remove old creds helpers"
```

---

## Task 4: Update `_sandbox_docker_run` for unified credentials injection

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Replace the SSH credentials block inside `_sandbox_docker_run`**

Find:
```fish
    # SSH deploy key (credentials-managed, not in volumes list)
    set -l creds_type (_sandbox_config_read_creds_type $project_path)
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_expand_vars (_sandbox_config_read_creds_key $project_path))
        set args $args -v "$key_path:/home/claude/.ssh/deploy_key:ro"
    end
```

Replace with:
```fish
    # Git auth injection
    set -l auth_type (_sandbox_config_read_git_auth_type $project_path)
    set args $args -e "SANDBOX_GIT_AUTH_TYPE=$auth_type"
    if test "$auth_type" = ssh; or test "$auth_type" = pat
        set -l creds_path (_sandbox_expand_vars (_sandbox_config_read_git_auth_path $project_path))
        set args $args -v "$creds_path:/home/claude/.gitcreds:ro"
    end
    if test "$auth_type" = ssh
        set -l prefer_ssh (_sandbox_config_read_git_auth_prefer_ssh $project_path)
        if test "$prefer_ssh" = true
            set args $args -e "SANDBOX_GIT_PREFER_SSH=1"
        end
    end
    set -l id_name (_sandbox_config_read_git_auth_identity_name $project_path)
    set -l id_email (_sandbox_config_read_git_auth_identity_email $project_path)
    if test -n "$id_name"
        set args $args -e "SANDBOX_GIT_NAME=$id_name"
    end
    if test -n "$id_email"
        set args $args -e "SANDBOX_GIT_EMAIL=$id_email"
    end
```

- [ ] **Step 2: Verify fish syntax**

```bash
fish -n functions/claude-sandbox.fish
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: update docker run to inject git_auth env vars and unified gitcreds mount"
```

---

## Task 5: Rewrite `_sandbox_git_auth_wizard`

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Replace `_sandbox_creds_wizard` with `_sandbox_git_auth_wizard`**

Find the entire function:
```fish
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
                set key_path (_sandbox_expand_vars $key_path)
            end

            ssh-keygen -t ed25519 -f $key_path -C "$project_name deploy key" -N ""
            or return 1

            echo ""
            echo "Key generated at $key_path"
            _sandbox_copy_pubkey "$key_path.pub"
            echo ""
            echo "GitHub : repo Settings -> Deploy keys -> Add deploy key  (enable \"Allow write access\" if needed)"
            echo "GitLab : repo Settings -> Repository -> Deploy keys"
            echo ""
            read -P "Press Enter when done to launch the sandbox..." _dummy

            _sandbox_config_write_creds_ssh $project_path $key_path

        case 2
            read -P "SSH key path: " key_path
            set key_path (_sandbox_expand_vars $key_path)
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
```

Replace with:
```fish
function _sandbox_git_auth_wizard
    # Usage: _sandbox_git_auth_wizard <project_path> <project_name>
    set -l project_path $argv[1]
    set -l project_name $argv[2]

    echo ""
    echo "No git credentials configured for \"$project_path\"."
    echo ""
    echo "  1. SSH deploy key  [Enter]"
    echo "  2. PAT (Personal Access Token)"
    echo "  3. Skip"
    echo ""
    read -P "Choice [1]: " choice
    if test -z "$choice"
        set choice 1
    end

    switch $choice
        case 1
            echo ""
            echo "  1. Generate a new deploy key"
            echo "  2. Use an existing key"
            echo ""
            read -P "Choice [1]: " ssh_choice
            if test -z "$ssh_choice"
                set ssh_choice 1
            end

            set -l default_path $HOME/.ssh/id_ed25519_$project_name
            switch $ssh_choice
                case 1
                    read -P "Key path [$default_path]: " key_path
                    if test -z "$key_path"
                        set key_path $default_path
                    else
                        set key_path (_sandbox_expand_vars $key_path)
                    end

                    ssh-keygen -t ed25519 -f $key_path -C "$project_name deploy key" -N ""
                    or return 1

                    echo ""
                    echo "Key generated at $key_path"
                    _sandbox_copy_pubkey "$key_path.pub"
                    echo ""
                    echo "GitHub : repo Settings -> Deploy keys -> Add deploy key  (enable \"Allow write access\" if needed)"
                    echo "GitLab : repo Settings -> Repository -> Deploy keys"
                    echo ""
                    read -P "Press Enter when done to launch the sandbox..." _dummy

                case 2
                    read -P "SSH key path: " key_path
                    set key_path (_sandbox_expand_vars $key_path)
                    if not test -f $key_path
                        echo "Error: key file not found: $key_path"
                        return 1
                    end

                case '*'
                    echo "Error: invalid choice '$ssh_choice'"
                    return 1
            end

            _sandbox_config_write_git_auth_ssh $project_path $key_path

        case 2
            read -P "Token file path: " token_path
            set token_path (_sandbox_expand_vars $token_path)
            if not test -f $token_path
                echo "Error: file not found: $token_path"
                return 1
            end
            _sandbox_config_write_git_auth_pat $project_path $token_path

        case 3
            _sandbox_config_write_git_auth_none $project_path
            return 0

        case '*'
            echo "Error: invalid choice '$choice'"
            return 1
    end

    # Identity step (SSH and PAT only)
    set -l default_name (git config --global user.name 2>/dev/null)
    set -l default_email (git config --global user.email 2>/dev/null)

    echo ""
    echo "Git identity for this project:"

    set -l name_prompt "  Name"
    if test -n "$default_name"
        set name_prompt "$name_prompt [$default_name]"
    end
    read -P "$name_prompt: " id_name
    if test -z "$id_name"
        set id_name $default_name
    end

    set -l email_prompt "  Email"
    if test -n "$default_email"
        set email_prompt "$email_prompt [$default_email]"
    end
    read -P "$email_prompt: " id_email
    if test -z "$id_email"
        set id_email $default_email
    end

    if test -n "$id_name"; or test -n "$id_email"
        _sandbox_config_write_git_auth_identity $project_path $id_name $id_email
    end
end
```

- [ ] **Step 2: Verify fish syntax**

```bash
fish -n functions/claude-sandbox.fish
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: rewrite credentials wizard as _sandbox_git_auth_wizard with SSH/PAT/Skip + identity step"
```

---

## Task 6: Rename `creds` subcommand to `git-auth` in main `claude-sandbox` function

**Files:**
- Modify: `functions/claude-sandbox.fish`

Four areas in the main `claude-sandbox` function need updating.

- [ ] **Step 1: Update top-level `--help` output**

Find:
```fish
        printf "  %-34s%s\n" "creds <action>"        "Manage per-project SSH credentials"
```
Replace with:
```fish
        printf "  %-34s%s\n" "git-auth <action>"     "Manage per-project git auth"
```

- [ ] **Step 2: Rename the `creds` subcommand dispatch block**

Find (the entire creds if-block start):
```fish
    # --- creds subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = creds
        set -l action $argv[2]
        if contains -- --help $argv
            echo "Usage: claude-sandbox creds {set [key-path]|show|clear|list}"
            echo ""
            printf "  %-22s%s\n" "set [key-path]" "Configure SSH key (runs wizard if no path given)"
            printf "  %-22s%s\n" "show"           "Print saved credential for current project"
            printf "  %-22s%s\n" "clear"          "Remove saved credential (will prompt on next launch)"
            printf "  %-22s%s\n" "list"           "List all saved project credentials"
            return 0
        end
        switch $action
            case set
                if test (count $argv) -ge 3
                    set -l key_path (_sandbox_expand_vars $argv[3])
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
                yq -r '(.projects // {}) | to_entries[] | select(.value.credentials != null) | "\(.key)\n  type: \(.value.credentials.type)" + (if .value.credentials.keyPath then "\n  keyPath: \(.value.credentials.keyPath)" else "" end)' $f
            case '*'
                echo "Usage: claude-sandbox creds {set [key-path]|show|clear|list}"
                return 1
        end
        return
    end
```

Replace with:
```fish
    # --- git-auth subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = git-auth
        set -l action $argv[2]
        if contains -- --help $argv
            echo "Usage: claude-sandbox git-auth {set|show|clear|list}"
            echo ""
            printf "  %-22s%s\n" "set"   "Configure git credentials (SSH or PAT)"
            printf "  %-22s%s\n" "show"  "Print saved git auth for current project"
            printf "  %-22s%s\n" "clear" "Remove saved git auth (will prompt on next launch)"
            printf "  %-22s%s\n" "list"  "List all saved project git auth"
            return 0
        end
        switch $action
            case set
                _sandbox_git_auth_wizard $PROJECT_PATH $PROJECT_NAME
            case show
                set -l t (_sandbox_config_read_git_auth_type $PROJECT_PATH)
                if test -z "$t"
                    echo "No git auth configured for $PROJECT_PATH"
                else
                    echo "type: $t"
                    if test "$t" = ssh; or test "$t" = pat
                        echo "path: "(_sandbox_config_read_git_auth_path $PROJECT_PATH)
                    end
                    if test "$t" = ssh
                        echo "prefer_ssh: "(_sandbox_config_read_git_auth_prefer_ssh $PROJECT_PATH)
                    end
                    set -l n (_sandbox_config_read_git_auth_identity_name $PROJECT_PATH)
                    set -l e (_sandbox_config_read_git_auth_identity_email $PROJECT_PATH)
                    if test -n "$n"; or test -n "$e"
                        echo "identity:"
                        echo "  name: $n"
                        echo "  email: $e"
                    end
                end
            case clear
                _sandbox_config_delete $PROJECT_PATH
                echo "Cleared git auth for $PROJECT_PATH (will prompt on next launch)"
            case list
                set -l f (_sandbox_config_file)
                if not test -f $f
                    echo "No git auth configured."
                    return
                end
                yq -r '(.projects // {}) | to_entries[] | select(.value.git_auth != null) | "\(.key)\n  type: \(.value.git_auth.type)" + (if .value.git_auth.path then "\n  path: \(.value.git_auth.path)" else "" end) + (if .value.git_auth.identity then "\n  name: \(.value.git_auth.identity.name)\n  email: \(.value.git_auth.identity.email)" else "" end)' $f
            case '*'
                echo "Usage: claude-sandbox git-auth {set|show|clear|list}"
                return 1
        end
        return
    end
```

- [ ] **Step 3: Update the launch flow**

Find:
```fish
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
```

Replace with:
```fish
    # Resolve git auth for this project
    set -l auth_type (_sandbox_config_read_git_auth_type $PROJECT_PATH)
    if test -z "$auth_type"
        _sandbox_git_auth_wizard $PROJECT_PATH $PROJECT_NAME
        or return 1
        set auth_type (_sandbox_config_read_git_auth_type $PROJECT_PATH)
    end

    # Verify credentials file exists if configured
    if test "$auth_type" = ssh; or test "$auth_type" = pat
        set -l creds_path (_sandbox_expand_vars (_sandbox_config_read_git_auth_path $PROJECT_PATH))
        if not test -f $creds_path
            echo "Error: credentials file not found: $creds_path"
            echo "Run 'claude-sandbox git-auth set' to reconfigure."
            return 1
        end
    end
```

- [ ] **Step 4: Verify fish syntax**

```bash
fish -n functions/claude-sandbox.fish
```
Expected: no output.

- [ ] **Step 5: Verify help output**

```bash
fish functions/claude-sandbox.fish --help
```
Expected: shows `git-auth <action>` entry (not `creds`).

```bash
fish functions/claude-sandbox.fish git-auth --help
```
Expected:
```
Usage: claude-sandbox git-auth {set|show|clear|list}

  set                    Configure git credentials (SSH or PAT)
  show                   Print saved git auth for current project
  clear                  Remove saved git auth (will prompt on next launch)
  list                   List all saved project git auth
```

- [ ] **Step 6: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: rename creds subcommand to git-auth; add PAT/identity to show/list"
```

---

## Task 7: Update tab completions

**Files:**
- Modify: `completions/claude-sandbox.fish`

- [ ] **Step 1: Replace `creds` with `git-auth` throughout**

Find:
```fish
set -l subcommands stop list creds mounts global
```
Replace with:
```fish
set -l subcommands stop list git-auth mounts global
```

Find:
```fish
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a creds  -d 'Manage per-project SSH credentials'
```
Replace with:
```fish
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a git-auth -d 'Manage per-project git auth'
```

Find the entire `# creds actions` block:
```fish
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
```
Replace with:
```fish
# git-auth actions
set -l git_auth_actions set show clear list
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth; and not __fish_seen_subcommand_from $git_auth_actions" \
    -a set   -d 'Configure git credentials (SSH or PAT)'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth; and not __fish_seen_subcommand_from $git_auth_actions" \
    -a show  -d 'Show current git auth'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth; and not __fish_seen_subcommand_from $git_auth_actions" \
    -a clear -d 'Remove saved git auth'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth; and not __fish_seen_subcommand_from $git_auth_actions" \
    -a list  -d 'List all project git auth'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth" \
    -l help -d 'Show usage'
```

- [ ] **Step 2: Verify fish syntax**

```bash
fish -n completions/claude-sandbox.fish
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add completions/claude-sandbox.fish
git commit -m "feat: rename creds to git-auth in tab completions"
```

---

## Spec Coverage Checklist

- [x] Wizard prompt updated — Task 5
- [x] 3 options (SSH default, PAT, Skip) — Task 5
- [x] SSH branch: generate or use existing key — Task 5
- [x] PAT branch: token file path — Task 5
- [x] Identity step after SSH/PAT — Task 5
- [x] `prefer_ssh: true` stored for SSH — Task 3 (`_sandbox_config_write_git_auth_ssh`)
- [x] `configurations.yml` schema: `git_auth` key with `type/path/prefer_ssh/identity` — Task 3
- [x] Remove `~/.gitconfig` bind mount — Task 1
- [x] Container injection: unified `/home/claude/.gitcreds` mount — Task 4
- [x] Container injection: `SANDBOX_GIT_AUTH_TYPE` env var — Task 4
- [x] Container injection: `SANDBOX_GIT_NAME/EMAIL` env vars — Task 4
- [x] Container injection: `SANDBOX_GIT_PREFER_SSH` env var — Task 4
- [x] `entrypoint.sh`: SSH config from `SANDBOX_GIT_AUTH_TYPE=ssh` — Task 2
- [x] `entrypoint.sh`: PAT credential helper from `SANDBOX_GIT_AUTH_TYPE=pat` — Task 2
- [x] `entrypoint.sh`: write `.gitconfig` from identity env vars — Task 2
- [x] `entrypoint.sh`: `url.insteadOf` from `SANDBOX_GIT_PREFER_SSH=1` — Task 2
- [x] `creds` subcommand → `git-auth` — Task 6
- [x] `git-auth set` always runs wizard — Task 6
- [x] `git-auth show` includes identity — Task 6
- [x] `git-auth list` uses `git_auth` key — Task 6
- [x] Launch flow updated to use `git_auth` helpers — Task 6
- [x] Error: credentials file missing → prompt to run `git-auth set` — Task 6
- [x] Tab completions updated — Task 7
