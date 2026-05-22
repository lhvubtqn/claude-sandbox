# Git Auth Wizard — Design Spec

**Date:** 2026-05-22
**Scope:** Replace the SSH-only credentials wizard with a unified SSH + PAT flow; add per-project git identity injection; remove the host `~/.gitconfig` bind mount.

---

## Overview

The current wizard only supports SSH deploy keys and stores credentials under `projects[$path].credentials` in `configurations.yml`. This redesign:

1. Adds PAT (Personal Access Token) as a second credential type
2. Captures per-project git identity (name, email) after credential selection
3. Injects everything into the container via env vars + a unified `/home/claude/.gitcreds` mount
4. Removes the host `~/.gitconfig` bind mount in favour of per-project identity

---

## Wizard Flow

Triggered on first launch (no `git_auth` configured) or via `claude-sandbox git-auth set`.

```
No git credentials configured for "/path/to/project".

  1. SSH deploy key  [Enter]
  2. PAT (Personal Access Token)
  3. Skip

Choice [1]:
```

- Pressing Enter with no input defaults to `1` (SSH).
- `3` saves `{type: none}` and skips the identity step.

### SSH branch
Same as today: generate new key or use existing. After key selection:
- Stores `git_auth.type = ssh`, `git_auth.path = <key_path>`, `git_auth.prefer_ssh = true`

### PAT branch
```
Token file path:
```
Must be an existing file. Stores `git_auth.type = pat`, `git_auth.path = <token_file_path>`.

### Identity step (SSH and PAT only)
```
Git identity for this project:
  Name  [<from ~/.gitconfig>]:
  Email [<from ~/.gitconfig>]:
```
Defaults are read with `git config --global user.name` / `user.email`. Blank input keeps the default.
Stores `git_auth.identity.name` and `git_auth.identity.email`.

---

## `configurations.yml` Schema

```yaml
projects:
  /home/you/myproject:
    git_auth:
      type: ssh          # "ssh" | "pat" | "none"
      path: ~/.ssh/id_ed25519_myproject
      prefer_ssh: true   # only present when type = ssh; adds url.insteadOf for github.com
      identity:
        name: Vincent Le
        email: dat@sandbox-software.dev
  /home/you/other-project:
    git_auth:
      type: none         # path and identity are absent
```

`prefer_ssh` rewrites `https://github.com/` → `git@github.com:` inside the container only.

**Global change:** remove from `global.container.volumes`:
```yaml
# removed:
# - ${HOME}/.gitconfig:/home/claude/.gitconfig:ro
```

---

## Container Injection (`_sandbox_docker_run`)

| Condition | Action |
|---|---|
| `type = ssh` or `type = pat` | Mount `git_auth.path` as `/home/claude/.gitcreds:ro` |
| Always | Pass `-e SANDBOX_GIT_AUTH_TYPE=<type>` |
| `identity` set | Pass `-e SANDBOX_GIT_NAME=...` and `-e SANDBOX_GIT_EMAIL=...` |
| `prefer_ssh = true` | Pass `-e SANDBOX_GIT_PREFER_SSH=1` |

---

## `entrypoint.sh`

Replaces the existing deploy-key block. Runs before `exec "$@"`.

```
if SANDBOX_GIT_AUTH_TYPE = ssh:
    write /home/claude/.ssh/config:
        Host *
          IdentityFile /home/claude/.gitcreds
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
    chmod 600 /home/claude/.ssh/config

if SANDBOX_GIT_AUTH_TYPE = pat:
    TOKEN = $(cat /home/claude/.gitcreds)
    write /home/claude/.git-credentials: https://<TOKEN>@github.com
    chmod 600 /home/claude/.git-credentials
    git config --global credential.helper "store --file /home/claude/.git-credentials"

if SANDBOX_GIT_NAME or SANDBOX_GIT_EMAIL set:
    git config --global user.name  "$SANDBOX_GIT_NAME"   (if set)
    git config --global user.email "$SANDBOX_GIT_EMAIL"  (if set)

if SANDBOX_GIT_PREFER_SSH = 1:
    git config --global url."git@github.com:".insteadOf "https://github.com/"
```

All `git config --global` calls write to `/home/claude/.gitconfig` (no bind mount, file is created fresh each container start).

---

## Fish Function Changes

### Renamed helpers

| Old name | New name |
|---|---|
| `_sandbox_config_read_creds_type` | `_sandbox_config_read_git_auth_type` |
| `_sandbox_config_read_creds_key` | `_sandbox_config_read_git_auth_path` |
| `_sandbox_config_write_creds_ssh` | `_sandbox_config_write_git_auth_ssh` |
| `_sandbox_config_write_creds_none` | `_sandbox_config_write_git_auth_none` |
| `_sandbox_creds_wizard` | `_sandbox_git_auth_wizard` |

### New helpers

- `_sandbox_config_write_git_auth_pat <project_path> <token_path>` — writes `{type: pat, path}`
- `_sandbox_config_write_git_auth_identity <project_path> <name> <email>` — writes `git_auth.identity`
- `_sandbox_config_read_git_auth_identity <project_path>` — returns `name\nemail` for display

### `creds` subcommand → `git-auth`

`show` output updated to include identity and PAT type. All internal references to `creds` renamed to `git-auth`.

`git-auth set` always runs the wizard (the old `creds set [key-path]` shortcut that set SSH directly is removed — type is now required context).

### Launch flow update

```
set -l auth_type (_sandbox_config_read_git_auth_type $PROJECT_PATH)
if test -z "$auth_type"
    _sandbox_git_auth_wizard $PROJECT_PATH $PROJECT_NAME
    or return 1
    set auth_type (_sandbox_config_read_git_auth_type $PROJECT_PATH)
end
```

SSH key existence check updated to use `_sandbox_config_read_git_auth_path`.

---

## Tab Completions (`completions/claude-sandbox.fish`)

- In the `$subcommands` list: replace `creds` with `git-auth`
- Top-level completion entry: replace `creds` with `git-auth`, update description to `Manage per-project git auth`
- `creds` actions block: rename guard `__fish_seen_subcommand_from creds` → `git-auth`, update `set` description to `Configure git credentials (SSH or PAT)`

---

## Error Cases

- PAT token file not found at launch → error + prompt to run `claude-sandbox git-auth set`
- SSH key not found at launch → same as today
- Empty name/email during identity step → keep default (do not write blank values)
