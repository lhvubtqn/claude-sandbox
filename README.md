# claude-sandbox

A Docker sandbox for running [Claude Code](https://claude.ai/code) with `--dangerously-skip-permissions`. The container is the blast radius boundary — Claude can run any command freely without risking the host system.

## What's inside

| Tool | Source |
|---|---|
| Rust + Cargo | via official Solana install script |
| Solana CLI (Agave) | via official Solana install script |
| Anchor + AVM | via official Solana install script |
| Node.js + npm + npx + Yarn | via official Solana install script |
| Python 3 + pip | Ubuntu 24.04 |
| Claude Code | via `claude.ai/install.sh` |

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) with WSL2 integration enabled for your distro
- [VS Code](https://code.visualstudio.com/) with the [Remote - Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension
- [fish shell](https://fishshell.com/)
- `xxd` (`sudo apt install xxd` if missing)
- `yq` (`sudo apt install yq` if missing)

## Setup

**1. Clone the repo**

```bash
git clone https://github.com/lhvubtqn/claude-sandbox ~/.claude-sandbox
```

**2. Copy your git identity into the sandbox**

```bash
cp ~/.gitconfig ~/.claude-sandbox/.gitconfig
```

This creates a sandbox-local git config that lives in the repo and is mounted into the container. Edit it independently from your host `~/.gitconfig` if needed.

**3. Install the fish function**

```bash
mkdir -p ~/.config/fish/functions
cp ~/.claude-sandbox/functions/claude-sandbox.fish ~/.config/fish/functions/
```

On first launch, `configurations.yml` is auto-initialized with default global mounts (`.gitconfig`, `skills/`, `rules/`).

**4. Build the image** (takes 10–20 minutes on first run)

```bash
docker compose -f ~/.claude-sandbox/docker-compose.yml build
```

**5. Log in to Claude** inside the container (one-time setup)

```bash
claude-sandbox  # from any project folder
# then in the VS Code terminal:
claude
```

Claude config and session are stored in the `claude-config` named volume — login persists across restarts.

## Usage

From any project folder:

```bash
cd ~/your-project
claude-sandbox
```

This will:
1. Start (or restart) the container with your project mounted at `/workspace/your-project`
2. Open VS Code attached to the running container

Inside the container, run Claude with full permissions:

```bash
claude --dangerously-skip-permissions
```

## How it works

- **Project mount**: your current folder binds to `/workspace/<project-name>`. Each project gets a unique path so `claude -r` sessions stay scoped correctly.
- **Claude auth**: `~/.claude` is bind-mounted from the host — your subscription login carries over automatically.
- **Persistent caches**: named Docker volumes keep Cargo, npm, Solana config, and the VS Code Server across restarts and image rebuilds.
- **Host networking**: services running on the host (e.g. Godot MCP) are reachable inside the container at `host.docker.internal:<port>`.
- **Per-repo SSH credentials**: on first launch in a project, a wizard prompts you to generate a deploy key, use an existing key, or skip. Your choice is saved per project path — subsequent launches are silent. See [Git credentials](#git-credentials) below.

## Volume map

| Volume | Path in container | Purpose |
|---|---|---|
| `cargo-registry` | `/root/.cargo/registry` | Cargo package cache |
| `cargo-git` | `/root/.cargo/git` | Cargo git dependencies |
| `rustup-downloads` | `/root/.rustup/downloads` | Rustup toolchain downloads |
| `npm-cache` | `/root/.npm` | npm cache |
| `solana-config` | `/root/.config/solana` | Solana keypairs and config |
| `vscode-server` | `/home/claude/.vscode-server` | VS Code Server (survives restarts) |
| `claude-config` | `/home/claude/.claude` | Claude Code auth, config, and session; `.claude.json` lives here and is symlinked to `/home/claude/.claude.json` by the entrypoint |
| `.gitconfig` (bind, ro) | `/home/claude/.gitconfig` | Git identity — repo-local copy, edit independently from host |
| `~/.claude-sandbox/skills/` (bind, ro) | `/home/claude/.claude/skills/` | Custom Claude Code skills, version-controlled in this repo |
| `~/.claude-sandbox/rules/` (bind, ro) | `/home/claude/.claude/rules/` | Global Claude Code rules, version-controlled in this repo |
| SSH deploy key (bind, ro) | `/home/claude/.ssh/deploy_key` | Per-project SSH deploy key; included in the generated override file when configured |
| `$PROJECT_PATH` (bind) | `/workspace/$PROJECT_NAME` | Your project files |

## Git credentials

On the first `claude-sandbox` launch in any project, a wizard runs:

```
No SSH credentials configured for "/home/you/your-project".

  1. Generate a new deploy key
  2. Use an existing key
  3. Skip (no git credentials)

Choice: _
```

Option 1 runs `ssh-keygen`, copies the public key to your clipboard, and walks you through adding it as a deploy key in GitHub or GitLab before launching. Options 2 and 3 save immediately. Your choice is remembered per project path in `~/.claude-sandbox/configurations.yml`.

Manage credentials with subcommands (run from the project directory):

```bash
claude-sandbox creds set [key-path]   # reconfigure (runs wizard if no path given)
claude-sandbox creds show             # print saved credential for current project
claude-sandbox creds clear            # remove saved credential (will prompt on next launch)
claude-sandbox creds list             # list all saved project credentials
```

Mount additional host resources (executables, assets, etc.) into the container on a per-project basis:

```bash
claude-sandbox mounts add /opt/godot:/usr/local/bin/godot:ro   # bind a host path into the container
claude-sandbox mounts list                                       # show configured mounts for current project
claude-sandbox mounts remove /opt/godot:/usr/local/bin/godot:ro # remove a mount
claude-sandbox mounts clear                                      # remove all extra mounts for current project
```

Mount specs use Docker bind-mount syntax: `<host-path>:<container-path>[:<options>]`. Common options: `ro` (read-only).

## Global workspace

Always-on mounts (applied to every sandbox session regardless of project) are listed in `configurations.yml` under `global.mounts`. The defaults, initialized on first launch, are:

```yaml
global:
  mounts:
    - ~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
    - ~/.claude-sandbox/skills:/home/claude/.claude/skills:ro
    - ~/.claude-sandbox/rules:/home/claude/.claude/rules:ro
```

Add skills to `~/.claude-sandbox/skills/` and rules to `~/.claude-sandbox/rules/` — they are committed to this repo and mounted read-only into every container.

Manage global mounts with subcommands (run from any directory):

```bash
claude-sandbox global mounts list                              # show all global mounts
claude-sandbox global mounts add ~/.foo:/bar:ro                # add a global mount
claude-sandbox global mounts remove ~/.foo:/bar:ro             # remove a global mount
claude-sandbox global mounts clear                             # remove all global mounts
```

## Rebuilding

After pulling changes or updating tool versions:

```bash
docker compose -f ~/.claude-sandbox/docker-compose.yml build
```

Named volumes are preserved across rebuilds.

## Deferred

- Per-stack profiles (different extension sets for different languages)
- Per-project devcontainer configs
- Multi-agent / swarm setup
