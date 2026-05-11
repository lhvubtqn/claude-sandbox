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

## Setup

**1. Clone the repo**

```bash
git clone https://github.com/lhvubtqn/claude-sandbox ~/.claude-sandbox
```

**2. Install the fish function**

```bash
mkdir -p ~/.config/fish/functions
cp ~/.claude-sandbox/functions/claude-sandbox.fish ~/.config/fish/functions/
```

**3. Build the image** (takes 10–20 minutes on first run)

```bash
PROJECT_PATH=/tmp PROJECT_NAME=build docker compose -f ~/.claude-sandbox/docker-compose.yml build
```

**4. Log in to Claude** inside the container (one-time setup)

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
- **Git commits work, push doesn't**: no SSH keys or credentials are mounted, so Claude can commit locally but cannot push.

## Volume map

| Volume | Path in container | Purpose |
|---|---|---|
| `cargo-registry` | `/root/.cargo/registry` | Cargo package cache |
| `cargo-git` | `/root/.cargo/git` | Cargo git dependencies |
| `rustup-downloads` | `/root/.rustup/downloads` | Rustup toolchain downloads |
| `npm-cache` | `/root/.npm` | npm cache |
| `solana-config` | `/root/.config/solana` | Solana keypairs and config |
| `vscode-server` | `/home/claude/.vscode-server` | VS Code Server (survives restarts) |
| `claude-config` | `/home/claude/.claude` | Claude Code auth, config, and session |
| `~/.claude.json` (bind) | `/home/claude/.claude.json` | Claude Code account state and onboarding flags |
| `$PROJECT_PATH` (bind) | `/workspace/$PROJECT_NAME` | Your project files |

## Rebuilding

After pulling changes or updating tool versions:

```bash
PROJECT_PATH=/tmp PROJECT_NAME=build docker compose -f ~/.claude-sandbox/docker-compose.yml build
```

Named volumes are preserved across rebuilds.

## Deferred

- Per-stack profiles (different extension sets for different languages)
- Per-project devcontainer configs
- Multi-agent / swarm setup
