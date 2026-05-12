# Per-Repo Git Credentials for claude-sandbox

## Overview

When running `claude-sandbox`, the user is prompted for (or reminded of) an SSH private key to inject into the container for that project. Credentials are stored per project path in a local config file. The container gets true isolation — no host SSH agent, no host keys, only the explicitly configured key.

## Data Model

`~/.claude-sandbox/project-creds.json` maps absolute project paths to credential records:

```json
{
  "/home/user/projects/myapp": { "type": "ssh", "keyPath": "/home/user/.ssh/id_ed25519_myapp" },
  "/home/user/projects/other": { "type": "none" }
}
```

- `"type": "ssh"` — inject the key at `keyPath` into the container
- `"type": "none"` — user explicitly skipped; no prompt on next launch

The file stores only key paths, never key content.

## Fish Function Flow

### Launch (`claude-sandbox`, no args)

1. Determine `PROJECT_PATH` (pwd) and `PROJECT_NAME` (basename)
2. Read `~/.claude-sandbox/project-creds.json` via `jq`
3. Look up entry for `PROJECT_PATH`:
   - **Entry exists, `type: ssh`**: load `keyPath`, verify file exists, set `SANDBOX_SSH_KEY_PATH`
   - **Entry exists, `type: none`**: proceed without credentials
   - **No entry**: print hint `"Tip: to create a repo-specific key: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_<name> -C \"<name> deploy key\" -N \"\""`, then prompt `"No credentials configured. Enter SSH key path (or Enter to skip):"`, save result (`ssh` or `none`)
4. Call `docker compose up -d --force-recreate` with `SANDBOX_SSH_KEY_PATH` in env
5. Open VS Code attached to container

### Subcommands

```
claude-sandbox creds set [key-path]   # configure SSH key for current dir; prompts if omitted
claude-sandbox creds show             # print saved credential for current dir
claude-sandbox creds clear            # remove saved credential for current dir (will prompt on next launch)
claude-sandbox creds list             # list all saved project paths and their key paths
```

All subcommands operate on `~/.claude-sandbox/project-creds.json` and do not restart the container.

## Docker Compose Changes

```yaml
volumes:
  - .gitconfig:/home/claude/.gitconfig:ro
  - ${SANDBOX_SSH_KEY_PATH:-.ssh_placeholder}:/home/claude/.ssh/repo_key:ro
```

- `.gitconfig` is a file committed to `~/.claude-sandbox/` (copied from host once at setup, then managed independently)
- `.ssh_placeholder` is a committed empty file used as the volume target when no key is configured

The `${HOME}/.gitconfig` host mount is removed.

## Dockerfile Changes

A new `entrypoint.sh` script is added and set as `ENTRYPOINT`. It writes `~/.ssh/config` only when the mounted key file is non-empty, then `exec "$@"` to hand off to `sleep infinity`:

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

The `command: sleep infinity` in `docker-compose.yml` becomes the CMD passed to the entrypoint.

## Dependencies

- `jq` must be installed on the host (used by the fish function to read/write `project-creds.json`)

## Setup (One-Time)

```bash
cp ~/.gitconfig ~/.claude-sandbox/.gitconfig
```

## Security Properties

- No host SSH agent is forwarded into the container
- Private key content never enters the config file
- `IdentitiesOnly yes` ensures the container cannot authenticate with any key other than the configured one
- The placeholder file is empty — if no key is configured, SSH has no credentials at all
