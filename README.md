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
claude-sandbox -g mounts --help
claude-sandbox -p <id|path> mounts --help
```

Use `-p/--project <id|path>` before any of `mounts`, `git-auth`, `open`,
`restart`, `stop`, or `ui` to target another project (by path, container hash,
or name). Use `-g` before `mounts` to manage the always-on global volumes.

Use `claude-sandbox open <path-or-container>` from anywhere to attach VS Code to a sandbox. Tab completion lists every existing container's path and hash.

Use `claude-sandbox restart <path-or-container>` to recreate a container with the current config — the way to apply changes from `claude-sandbox mounts add` and friends. On reopen, claude-sandbox detects when a container's config has drifted from `configurations.yml`, shows what changed, and offers to restart.

### Environment variables

The `container:` block accepts an `environment:` key, passed to the container as
`docker run -e`. Both docker-compose forms work — a map or a `- KEY=value` list
— and values expand `${WORKDIR}`, `${HOME}`, and leading `~/`. There is no
`mounts`-style CLI helper, so edit `configurations.yml` directly and
`claude-sandbox restart` to apply.

Define it **under a project** to scope it to that sandbox only (e.g. GUI
plumbing you don't want enabled for every container); putting it under `global`
would apply it to all containers. Global and per-project entries are merged.

```yaml
projects:
  /home/you/my-app:
    container:
      environment:
        MY_VAR: hello
```

Like volumes, env entries participate in config-drift detection.

### GUI apps (WSLg)

To run a desktop app (Godot editor, Electron, GTK/Qt) inside a sandbox, set
`ui_mode: wslg` on that project — it sits at the project level, alongside
`git_auth`:

```bash
claude-sandbox ui wslg      # set ui_mode: wslg for the current project
claude-sandbox restart      # apply it
claude-sandbox ui           # print the current mode
claude-sandbox ui none      # back to headless
```

When `wslg` is set, launching the container automatically:

- mounts the host WSLg sockets (`/tmp/.X11-unix`, `/mnt/wslg`),
- sets the display env (`DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`,
  `PULSE_SERVER` for audio), and
- has the entrypoint install the GUI runtime libraries (X11/Wayland/GL/audio) —
  only the ones actually missing, so warm starts stay fast.

Because the libs are installed at container start (not baked into the image),
the headless base image stays lean for every other sandbox. The trade-off: a
fresh container's first boot with `ui_mode: wslg` spends ~30–60s installing
libs. The mode is **WSL-only** — on a non-WSL host the launcher refuses to start
the container and tells you to set `ui_mode: none`. Toggling `ui_mode`
participates in config-drift detection, so an open project will offer to restart
when you change it.

---

## How it works

- **Per-project containers**: each project runs in a dedicated container named `claude-sandbox-<hash>` where the hash is derived from the project path. Running `claude-sandbox` in a project that is already open re-attaches VS Code without restarting the container or interrupting any running Claude session.
- **Config drift**: each container records a snapshot of the config it was built from (a `claude-sandbox.config-snapshot` label). Reopening a project compares that snapshot to the current `configurations.yml`; if they differ it lists the changes and offers to restart. `claude-sandbox restart` applies changes on demand.
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
| `npm-globals` | `/home/claude/.npm-globals` | Globally-installed npm packages (`npm install -g`) |
| `pipx` | `/home/claude/.pipx` | pipx-installed apps and their venvs (`pipx install`) |
| `~/.gitconfig` (bind, ro) | `/home/claude/.gitconfig` | Git identity from the host |
| `<repo>/skills/` (bind, ro) | `/home/claude/.claude/skills/` | Custom Claude Code skills, version-controlled in this repo |
| `<repo>/rules/` (bind, ro) | `/home/claude/.claude/rules/` | Global Claude Code rules, version-controlled in this repo |
| SSH deploy key (bind, ro) | `/home/claude/.ssh/deploy_key` | Per-project SSH deploy key |
| `$PROJECT_PATH` (bind) | `/workspace/$PROJECT_NAME` | Your project files |

## Upgrading

After pulling new commits that introduce additional named volumes, your existing `configurations.yml` does not pick them up automatically (the template only seeds the config file on first install). For `npm-globals` and `pipx` specifically, the new env vars (`NPM_CONFIG_PREFIX`, `PIPX_HOME`, `PIPX_BIN_DIR`, `PATH` entries) also live in the Docker image, so you need both an image rebuild and a config update.

Note that `make install` only builds the image when one does not already exist — it does not rebuild on Dockerfile changes. Use `make build` (or `make build-no-cache`) to pick up image changes.

```bash
make build                                                         # rebuild the image
claude-sandbox -g mounts add npm-globals:/home/claude/.npm-globals  # opt the global config into the new volume
claude-sandbox -g mounts add pipx:/home/claude/.pipx                # cache pipx-installed apps
```

The next time you open or restart a project, `claude-sandbox` will detect the config drift, show the new entry, and offer to recreate the container. Accept the restart and `npm install -g` / `pipx install` results will persist from then on.
