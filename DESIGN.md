# claude-sandbox — Design & Architecture

> A companion to the user-facing [README](./README.md). The README tells you *how to use*
> claude-sandbox; this document explains *how it is built and why*.

---

## 1. What it is, in one sentence

claude-sandbox runs [Claude Code](https://claude.ai/code) with `--dangerously-skip-permissions`
inside a per-project Docker container, so Claude can execute any command freely while the
**container is the blast-radius boundary** — nothing it does can reach the host.

Everything in the design follows from that single premise. The container must be disposable,
isolated, and reproducible; the host must hand it the *minimum* it needs (one project folder,
one git credential, a few shared caches) and nothing more.

---

## 2. The mental model

Five concepts carry almost the entire design. Internalize these and the rest is detail.

### Per-project container
Each project gets its own container named `claude-sandbox-<hash>`, where `<hash>` is the
first 8 hex chars of `sha256(absolute project path)`. The name is deterministic, so the CLI
can always find a project's container without bookkeeping, and two projects never collide.
Opening a second project launches a second container next to the first — parallel VS Code
windows, parallel Claude sessions, no interference. Build caches are still shared (see below),
so isolation costs disk for project files but not for toolchains.

### Config lives in YAML, not in compose
There is **one source of truth** for runtime configuration: `configurations.yml`. It is a
two-level document:

```yaml
global:               # applies to every container
  container: { image, volumes, security_opt, extra_hosts, environment }
projects:
  /abs/path/to/proj:  # keyed by absolute project path
    container: { ... } # per-project overrides, merged onto global
    git_auth: { ... }  # per-project credential + identity
    ui_mode: none|wslg
```

Merge semantics are fixed and simple: **scalars** (like `image`) — project overrides global;
**lists** (`volumes`, `security_opt`, `extra_hosts`) — project entries *append* after global
ones, never replace; `git_auth`/`ui_mode` are project-only. The launcher reads this file,
assembles a `docker run` command, and runs it. `docker compose` is retained for **building the
image only** — it plays no part in running containers.

### Config snapshot & config drift
A container's `docker run` arguments are frozen at creation time. So when you edit
`configurations.yml`, an *already-running* container is now stale. claude-sandbox makes that
visible and fixable:

- At creation, the launcher renders the **entire effective config** to a canonical, sorted,
  tab-delimited string (`_sandbox_render_config`) and stamps it onto the container as a
  base64-encoded Docker label: `claude-sandbox.config-snapshot`.
- On reopen, it re-renders the *current* config and line-diffs it against the decoded label.
  Any difference is **config drift** — shown to you as category-tagged `+`/`-` lines — and you
  are prompted (default *Yes*) to recreate the container. `claude-sandbox restart` does the
  same recreation unconditionally.

`_sandbox_render_config` is the single definition of "what counts as config." Add a tracked
option in exactly one place and it flows into both the stored snapshot and the diff.

### Path variables (`${WORKDIR}`, `${HOME}`, `~/`)
Config values are portable templates. Three tokens are expanded at runtime, in order
WORKDIR → HOME → ~: `${WORKDIR}` (the repo / config dir), `${HOME}`, and a leading `~/`. After
expansion, a host side starting with `/` is a **bind mount**; anything else is a **named
volume**. Snapshots store the *raw* (unexpanded) form — expansion is deterministic, so raw-vs-raw
diffing is valid and reads better.

### Target resolution
Any project is addressable three interchangeable ways, all collapsing to one canonical
`target_path`: by **filesystem path** (works even before the container exists, so you can
pre-seed config), by **container hash**, or by **full container name**. The
`_sandbox_resolve_target` helper tries the value as a container ref (reading the
`claude-sandbox.project` label) first, then falls back to `realpath`. Leading `-p/--project`
flags select a target up front so every subcommand is target-agnostic; `-g/--global` targets
the always-on global config instead.

---

## 3. How the pieces fit together

```
 ┌─────────────────────────── HOST (WSL2 + fish) ───────────────────────────┐
 │                                                                          │
 │  functions/claude-sandbox.fish   ← the entire CLI (~1150 lines of fish)  │
 │      • reads/writes configurations.yml (via kislyuk yq)                  │
 │      • resolves target, merges global+project config                     │
 │      • assembles `docker run` / `docker start` / reattach                │
 │      • renders + diffs config snapshots (drift detection)                │
 │      • runs the git-auth wizard                                          │
 │      • attaches VS Code (hex-encoded container URI)                       │
 │                                                                          │
 │  configurations.yml      ← live, user-specific, GIT-IGNORED               │
 │      ↑ bootstrapped on first use from ↓                                   │
 │  configurations.yml.template  ← tracked, uses ${WORKDIR}/${HOME} tokens   │
 │                                                                          │
 │  Makefile  → `docker build` only.   completions/ → fish tab-completion.   │
 └────────────────────────────────┬─────────────────────────────────────────┘
                                   │ docker run (per project)
                                   ▼
 ┌──────────────────── CONTAINER  claude-sandbox-<hash> ────────────────────┐
 │  ubuntu:24.04, non-root user `claude` (UID 1000)                          │
 │  baked toolchains: Rust, Solana CLI, Anchor, Node/nvm, Claude Code        │
 │                                                                          │
 │  /entrypoint.sh runs first, every start:                                 │
 │      • from SANDBOX_GIT_* env → writes ~/.ssh/config OR ~/.git-credentials │
 │        OR git identity OR https→ssh rewrite                               │
 │      • if SANDBOX_UI_MODE=wslg → apt-installs only the missing GUI libs    │
 │      • symlinks ~/.claude/.claude.json into place, then exec sleep ∞      │
 │                                                                          │
 │  bind:  $PROJECT → /workspace/<name>                                      │
 │  bind:  one git credential → /home/claude/.gitcreds  (ro)                 │
 │  named volumes: caches + auth (see Volume map in README)                 │
 │  label: claude-sandbox.project=<abs path>                                 │
 │  label: claude-sandbox.config-snapshot=<base64 render>                    │
 └──────────────────────────────────────────────────────────────────────────┘
```

The three artifacts you actually edit are the **Dockerfile** (what's baked into the image),
**`configurations.yml`** (per-machine runtime config), and the **fish function** (the CLI logic).

---

## 4. Setup, briefly

`make install` symlinks the fish function, the `clsb` alias, and completions into
`~/.config/fish/`, and builds the image *only if one doesn't already exist*. Dockerfile changes
therefore need an explicit `make build` (or `make build-no-cache`). First build takes 10–20
minutes because it compiles the full Rust/Solana/Anchor/Node toolchain. See the README for
prerequisites (`xxd`, `yq`, fish, Docker Desktop + WSL2) and day-to-day commands.

The live `configurations.yml` is **bootstrapped lazily**: the `_sandbox_config_file` helper —
called by every config read/write — notices the file is missing, copies `configurations.yml.template`
through `sed`, and expands the path tokens to absolute paths. The template is tracked; the live
file is git-ignored, so per-machine credentials and paths never get committed.

---

## 5. Subsystem deep-dives

### 5.1 The image (Dockerfile)
- **Base** `ubuntu:24.04`. The shipped `ubuntu` user (UID 1000) is *renamed* to `claude` rather
  than created fresh — `--dangerously-skip-permissions` refuses to run as root, so a non-root
  user with passwordless sudo is mandatory.
- **Lean by aggressive purge.** The official Solana installer drags in the full ~840 MB LLVM dev
  stack; bindgen / `anchor build` only need the `libclang1-18` runtime lib. That lib is installed
  *first* (marked `manual` so it survives), then the entire dev stack is purged **in the same
  RUN layer** as the install — a later layer can't reclaim space already committed. Rust's bundled
  offline HTML docs (~800 MB) and all man/doc/info pages are stripped the same way.
- **Volume-backed dirs are pre-created in the image** (`.vscode-server`, `.ssh`, `.npm-globals`,
  `.pipx`) so they carry correct `claude:claude` ownership — Docker only seeds a named volume from
  the image when the source path exists *and* the volume is empty.
- **All tool paths are baked into `ENV PATH`** so non-login shells (and Claude's command exec) find
  every tool without sourcing a profile. A stable `~/.nvm/default-node-bin` symlink decouples PATH
  from the exact node version.

### 5.2 Caches: image-controlled vs. user-controlled state
A recurring decision: separate state the *image* owns from state the *user* owns, and put only the
latter in a named volume. The clearest case is **npm globals**. Rather than mount all of `~/.nvm`
(which would shadow the image's node tree and freeze it), a dedicated npm *prefix* —
`/home/claude/.npm-globals`, selected via `NPM_CONFIG_PREFIX` — holds only user-installed globals
in the `npm-globals` volume. Consequences: image node bumps actually take effect, `nvm install` of
a newer node doesn't nuke your globals, and a corrupted cache is resettable with
`docker volume rm npm-globals` without touching node/nvm. `pipx` follows the same pattern
(`PIPX_HOME`/`PIPX_BIN_DIR` under the `pipx` volume). Cargo, rustup, npm, Solana config, and the
VS Code Server are likewise named volumes — shared across *all* project containers, so isolation
never costs you re-downloaded toolchains. (See the README **Volume map** for the full table.)

### 5.3 Git auth: one mount, env-driven entrypoint
Credentials never leak from the host agent or host keys. Instead, per project you pick **one**
credential, stored under `projects.<path>.git_auth`:

```yaml
git_auth:
  type: ssh | pat | none
  path: <host path to key or token file>
  prefer_ssh: true          # ssh only: rewrite https→ssh inside the container
  identity: { name, email } # synthesized into .gitconfig at start
```

At launch the chosen credential is bind-mounted read-only at the single fixed path
`/home/claude/.gitcreds`, and `SANDBOX_GIT_*` env vars carry the type and identity. The
**entrypoint** does the rest at every container start: for `ssh` it writes `~/.ssh/config` with
`IdentitiesOnly yes` + `StrictHostKeyChecking accept-new` (the container can authenticate with
*only* the configured key); for `pat` it writes `~/.git-credentials` and wires the store helper;
identity goes into a freshly synthesized `.gitconfig` (there is no host `.gitconfig` bind mount at
all); `prefer_ssh` adds an `insteadOf` rewrite scoped to the container. A first-launch **wizard**
(`claude-sandbox git-auth set`) walks SSH-generate / SSH-existing / PAT / skip, and persists a
first-class `none` so it never re-prompts. This subsystem evolved from an SSH-only,
`project-creds.json`/`jq` design into the unified, type-tagged, `yq`-backed `git_auth` schema.

### 5.4 Container lifecycle & drift
The launcher (`_sandbox_launch`) is **idempotent**, keyed on `docker inspect` status: *running* →
reattach VS Code without disturbing a live Claude session; *exited/created/paused* → `docker start`;
*not found* → assemble and `docker run`. Before starting a reusable container it runs the drift
check (§2) and, on any drift, shows the diff and prompts to recreate. Recreation is one shared code
path — `_sandbox_preflight` (Docker + git-auth checks) → `_sandbox_recreate` (stop → rm →
`docker run`) → `_sandbox_attach` (hex-encode `{"containerName":...}` into a `vscode-remote://`
URI) — reused by `restart`, the drift "Yes" branch, and the bare command alike. Pre-snapshot
containers need no migration: a missing label decodes to empty, so the whole config reads as added
and the container simply registers as drifted on next open.

### 5.5 GUI apps (WSLg), opt-in per project
Desktop apps (Godot editor, Electron, GTK/Qt) need X11/Wayland/GL/audio runtime libs that would
bloat the base image for every headless sandbox. So they are **not** baked in. Setting
`ui_mode: wslg` on a project makes the launcher mount the host WSLg sockets and set the display
env, and makes the **entrypoint install only the missing libs** on start (`dpkg -s` check per
package) — warm starts stay a no-op, the first boot of a fresh GUI container pays ~30–60 s once.
The mode is WSL-only and participates in drift detection. (Full usage in the README.)

---

## 6. Decision log — the "why" behind recurring choices

| Decision | Rationale |
|---|---|
| **One container per project**, hash-named | Parallel sessions without interference; deterministic lookup; shared caches keep the cost to project-file disk only. Replaced a single shared `claude-sandbox` container that died whenever a second project launched. |
| **`docker run` from YAML, compose only for build** | The base compose file stays static and committable; all per-machine runtime config lives in one readable `configurations.yml`. Eliminated the per-launch `docker-compose.override.yml`. |
| **`global` / `projects` two-level schema, append-only merge** | A single source of truth for "what mounts into every session"; per-project config layers on top without ever having to restate or override globals. |
| **kislyuk `yq`, not mikefarah `yq`** | The Ubuntu-packaged `yq` is jq-compatible; the project standardizes on it for all reads/writes. (`jq` was kept only for the one-time JSON→YAML migration.) |
| **Config snapshot as a base64 Docker label** | Lets a container carry its own creation-time config baseline with zero external state; base64 keeps a multi-line render in one safe label value, matching the existing hex-encoding pattern used for the VS Code URI. |
| **Raw (unexpanded) values in snapshots, each category self-sorted** | Expansion is deterministic so raw-vs-raw diffing is valid and more readable; self-sorting means reordering YAML entries isn't mistaken for drift. |
| **Drift prompt defaults to Yes, but never auto-destroys** | The common case (you just edited config) is "apply it"; on EOF/non-interactive the `read` fails and defaults to *No*, so a running Claude session is never killed unattended. The diff is always shown first. |
| **One credential per project, env-driven entrypoint, no host agent/keys** | Keeps the isolation boundary intact — the container only ever sees the single credential you explicitly chose, and `.gitconfig` is synthesized fresh rather than bind-mounted. |
| **Dedicated cache *prefixes* (npm-globals, pipx), not whole-tree mounts** | Separates image-controlled state (nvm, node, baked tools) from user-controlled state (installed globals), so image upgrades take effect and a corrupt cache is independently resettable. |
| **GUI libs installed at entrypoint, not baked** | Headless base image stays lean for every non-GUI sandbox; only `ui_mode: wslg` projects pay the install cost, and only for the packages actually missing. |
| **`-p/--project` / `-g` front-door flags; `global` keyword removed** | A single up-front target resolution makes every subcommand target-agnostic and addressable by path (even pre-container), hash, or name. The old `global mounts` subcommand became `-g mounts`. |
| **Lazy template→live config bootstrap, live file git-ignored** | Per-machine credentials/paths never get committed; the tracked `.template` seeds an absolute-path live config on first use with no separate install step. |

---

## 7. Where to look next

- **`functions/claude-sandbox.fish`** — the CLI itself; `_sandbox_render_config`,
  `_sandbox_resolve_target`, `_sandbox_launch`, and `_sandbox_recreate` are the load-bearing helpers.
- **`Dockerfile` / `entrypoint.sh`** — image contents and per-start credential/UI wiring.
- **`README.md`** — usage, command reference, and the full volume map.
