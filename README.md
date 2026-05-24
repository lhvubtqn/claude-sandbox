# claude-sandbox

A Docker sandbox for running [Claude Code](https://claude.ai/code) with `--dangerously-skip-permissions`. The container is the blast radius boundary — Claude can run any command freely without risking the host system.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) with WSL2 integration enabled for your distro
- [VS Code](https://code.visualstudio.com/) with the [Remote - Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension
- [fish shell](https://fishshell.com/)
- `xxd` (`sudo apt install xxd` if missing)
- `yq` (`sudo apt install yq` if missing)

## Setup

**1. Clone the repo**

```bash
git clone https://github.com/lhvubtqn/claude-sandbox
```

**2. Install** (builds the Docker image on first run — takes 10–20 minutes)

```bash
cd claude-sandbox && make install
```

## Use it

From any project folder:

```bash
claude-sandbox
```

Opens VS Code attached to a container for the current project. Each project gets its own container — running `claude-sandbox` from a second project opens a second VS Code window without touching the first.

Inside the container:

```bash
yolo
```

Runs Claude with full permissions (`claude --dangerously-skip-permissions`).

## Quick reference

```bash
claude-sandbox --help
claude-sandbox global --help
```

Use `claude-sandbox open <path-or-container>` from anywhere to attach VS Code to a sandbox. Tab completion lists every existing container's path and hash.

---

## How it works

- **Per-project containers**: each project runs in a dedicated container named `claude-sandbox-<hash>` where the hash is derived from the project path. Running `claude-sandbox` in a project that is already open re-attaches VS Code without restarting the container or interrupting any running Claude session.
- **Project mount**: your current folder binds to `/workspace/<project-name>`. Each project gets a unique path so `claude -r` sessions stay scoped correctly.
- **Claude auth**: the `claude-config` named volume holds your subscription login — it is shared across all project containers.
- **Persistent caches**: named Docker volumes keep Cargo, npm, Solana config, and the VS Code Server across restarts and image rebuilds. All project containers share these caches.
- **Host networking**: services running on the host (e.g. Godot MCP) are reachable inside the container at `host.docker.internal:<port>`.
- **Per-repo SSH credentials**: on first launch in a project, a wizard prompts you to configure a deploy key or skip. Your choice is saved per project path — subsequent launches are silent.

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
| `~/.gitconfig` (bind, ro) | `/home/claude/.gitconfig` | Git identity from the host |
| `<repo>/skills/` (bind, ro) | `/home/claude/.claude/skills/` | Custom Claude Code skills, version-controlled in this repo |
| `<repo>/rules/` (bind, ro) | `/home/claude/.claude/rules/` | Global Claude Code rules, version-controlled in this repo |
| SSH deploy key (bind, ro) | `/home/claude/.ssh/deploy_key` | Per-project SSH deploy key |
| `$PROJECT_PATH` (bind) | `/workspace/$PROJECT_NAME` | Your project files |
