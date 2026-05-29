# Persistent npm Globals Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist `npm install -g` results across container recreation and share them across all project containers via a dedicated npm prefix backed by a named volume.

**Architecture:** A new named volume `npm-globals` is mounted at `/home/claude/.npm-globals` in every container (declared in the global `volumes` list). The image sets `NPM_CONFIG_PREFIX=/home/claude/.npm-globals` and adds `/home/claude/.npm-globals/bin` to `PATH`, so `npm install -g X` writes into the volume and `X` resolves from it. nvm and the image-baked node version are untouched — only the layer of user-installed globals lives in the volume.

**Tech Stack:** Docker, Dockerfile `ENV`/`RUN`, named volumes, `configurations.yml` (yaml), fish shell (existing `claude-sandbox global mounts add` for end-user opt-in path).

**Testing note:** This project has no automated test harness. Verification follows the existing convention: rebuild the image, recreate a container, run shell commands inside it, and observe expected output. Smoke-test tasks (Tasks 4–7) are part of the plan and must not be skipped — they are how correctness is confirmed.

**Spec:** `docs/superpowers/specs/2026-05-29-npm-globals-cache-design.md`.

---

### Task 0: Create a feature branch

**Files:**
- None (git only)

- [ ] **Step 1: Branch off `master`**

```bash
git checkout master
git pull --ff-only
git checkout -b feat/npm-globals-cache
```

Expected: `Switched to a new branch 'feat/npm-globals-cache'`.

---

### Task 1: Pre-create the npm-globals dir and set `NPM_CONFIG_PREFIX` + `PATH` in the Dockerfile

This task changes the image. Three additions:
1. Pre-create `/home/claude/.npm-globals` so the named volume initializes with `claude:claude` ownership.
2. Add `ENV NPM_CONFIG_PREFIX=/home/claude/.npm-globals` so npm writes globals there.
3. Extend `ENV PATH` to include `/home/claude/.npm-globals/bin` (inserted just before `default-node-bin`, so user-installed globals sit in the same band as other user tool dirs).

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Pre-create the dir in the existing `mkdir -p` line**

Edit `Dockerfile`. Locate lines 34–35 (the `mkdir -p /home/claude/.vscode-server /home/claude/.ssh` block):

Replace:

```dockerfile
RUN mkdir -p /home/claude/.vscode-server /home/claude/.ssh && \
    chmod 700 /home/claude/.ssh
```

With:

```dockerfile
RUN mkdir -p /home/claude/.vscode-server /home/claude/.ssh /home/claude/.npm-globals && \
    chmod 700 /home/claude/.ssh
```

Rationale: Docker only seeds a named volume from the image when the source path exists in the image **and** the volume is empty. The directory is created after `USER claude` so it inherits `claude:claude` ownership — the first-time volume init then carries that ownership, and `npm install -g` (running as `claude`) can write into it without sudo.

- [ ] **Step 2: Add `NPM_CONFIG_PREFIX` and update `PATH`**

Edit `Dockerfile`. Locate lines 41–42:

```dockerfile
ENV NVM_DIR=/home/claude/.nvm
ENV PATH="/home/claude/.cargo/bin:/home/claude/.local/share/solana/install/active_release/bin:/home/claude/.avm/bin:/home/claude/.local/bin:/home/claude/.nvm/default-node-bin:${PATH}"
```

Replace those two lines with:

```dockerfile
ENV NVM_DIR=/home/claude/.nvm
ENV NPM_CONFIG_PREFIX=/home/claude/.npm-globals
ENV PATH="/home/claude/.cargo/bin:/home/claude/.local/share/solana/install/active_release/bin:/home/claude/.avm/bin:/home/claude/.local/bin:/home/claude/.npm-globals/bin:/home/claude/.nvm/default-node-bin:${PATH}"
```

The `NPM_CONFIG_PREFIX` env var beats any project-local `.npmrc` `prefix=` line in npm's resolution order. The `PATH` entry is inserted between `.local/bin` and `.nvm/default-node-bin` — pick that exact position to keep the diff minimal and the user-tool band contiguous.

- [ ] **Step 3: Diff-check the change**

Run:

```bash
git diff Dockerfile
```

Expected: exactly three modified lines — the `mkdir -p ...` line gets `/home/claude/.npm-globals` appended, one new `ENV NPM_CONFIG_PREFIX=...` line is inserted, and the `ENV PATH=...` line gains `/home/claude/.npm-globals/bin:` before `/home/claude/.nvm/default-node-bin`. Nothing else changes.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: bake NPM_CONFIG_PREFIX and pre-create .npm-globals in image"
```

---

### Task 2: Declare the `npm-globals` volume in the configuration template

The template is what new installs of `claude-sandbox` seed their `configurations.yml` from. Existing users will opt in via `claude-sandbox global mounts add` in Task 5; that is the supported upgrade path.

**Files:**
- Modify: `configurations.yml.template`

- [ ] **Step 1: Add the volume entry**

Edit `configurations.yml.template`. Locate the global `volumes:` block (lines 8–16). Insert `- npm-globals:/home/claude/.npm-globals` after the `npm-cache` line:

Before:

```yaml
    volumes:
      # Persistent storage for Claude's configuration, credentials, and caches
      - claude-config:/home/claude/.claude
      - cargo-registry:/home/claude/.cargo/registry
      - cargo-git:/home/claude/.cargo/git
      - rustup-downloads:/home/claude/.rustup/downloads
      - npm-cache:/home/claude/.npm
      - solana-config:/home/claude/.config/solana
      - vscode-server:/home/claude/.vscode-server
```

After:

```yaml
    volumes:
      # Persistent storage for Claude's configuration, credentials, and caches
      - claude-config:/home/claude/.claude
      - cargo-registry:/home/claude/.cargo/registry
      - cargo-git:/home/claude/.cargo/git
      - rustup-downloads:/home/claude/.rustup/downloads
      - npm-cache:/home/claude/.npm
      - npm-globals:/home/claude/.npm-globals
      - solana-config:/home/claude/.config/solana
      - vscode-server:/home/claude/.vscode-server
```

- [ ] **Step 2: Diff-check**

```bash
git diff configurations.yml.template
```

Expected: exactly one added line: `      - npm-globals:/home/claude/.npm-globals`.

- [ ] **Step 3: Commit**

```bash
git add configurations.yml.template
git commit -m "feat: add npm-globals named volume to configuration template"
```

---

### Task 3: Document the new volume in the README

Two doc additions: a row in the volume map table, and a short upgrade note pointing existing users at `claude-sandbox global mounts add`.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the volume map row**

Edit `README.md`. Locate the volume map table (line 70 onwards). After the `vscode-server` row (line 77), insert the new row. The existing block:

```markdown
| `vscode-server` | `/home/claude/.vscode-server` | VS Code Server (survives restarts) |
| `claude-config` | `/home/claude/.claude` | Claude Code auth, config, and session |
```

Becomes:

```markdown
| `vscode-server` | `/home/claude/.vscode-server` | VS Code Server (survives restarts) |
| `claude-config` | `/home/claude/.claude` | Claude Code auth, config, and session |
| `npm-globals` | `/home/claude/.npm-globals` | Globally-installed npm packages (`npm install -g`) |
```

The row is inserted *after* `claude-config` rather than near `npm-cache` to keep the existing ordering (named caches first, binds after) intact while placing the new row at the end of the named-volume block. If you prefer adjacency with `npm-cache`, that is acceptable too — the table ordering is informational.

- [ ] **Step 2: Add an upgrade note for existing installs**

Edit `README.md`. After the volume map (after line 83 in the current file — i.e. after the last row of the volume table, which ends the file), append a new `## Upgrading` subsection. Copy the following content verbatim onto the end of the file (four-backtick outer fence here in the plan only — what you paste into the README is everything between the outer fences, which itself contains a normal three-backtick ` ```bash ` block):

````
## Upgrading

After pulling new commits that introduce additional named volumes, your existing `configurations.yml` does not pick them up automatically (the template only seeds the config file on first install). Apply the new `npm-globals` volume to existing installs with:

```bash
claude-sandbox global mounts add npm-globals:/home/claude/.npm-globals
```

The next time you open or restart a project, `claude-sandbox` will detect the config drift, show the new entry, and offer to recreate the container. Accept the restart and `npm install -g` results will persist from then on.
````

- [ ] **Step 3: Diff-check**

```bash
git diff README.md
```

Expected: one inserted table row and one new `## Upgrading` subsection at the end of the file. No other lines touched.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document npm-globals volume and existing-install upgrade step"
```

---

### Task 4: Rebuild the image and verify the env vars and pre-created dir

The Dockerfile rebuild is the first place the changes are observable. This task confirms the image carries the right `NPM_CONFIG_PREFIX`, `PATH`, and pre-created directory **before** we wire up the volume in the next task. If something is wrong here, fix Task 1 before proceeding.

**Files:**
- None (verification only)

- [ ] **Step 1: Rebuild the image**

From the repo root:

```bash
make install
```

This rebuilds the `claude-sandbox` image. Expected: completes successfully; rebuild only re-runs layers from the `mkdir -p` line forward (cached above it). Typical duration on a warm build is a couple of minutes; cold rebuilds take 10–20 minutes per the README.

- [ ] **Step 2: Verify the env vars in a fresh container, *without* the new volume yet**

Run a one-off container directly (bypassing `claude-sandbox` so no host config is involved):

```bash
docker run --rm claude-sandbox bash -lc 'echo "prefix=$NPM_CONFIG_PREFIX"; echo "PATH=$PATH"; npm config get prefix; ls -la /home/claude/.npm-globals'
```

Expected output (one block, lines in any order is fine; the key assertions are below):

```
prefix=/home/claude/.npm-globals
PATH=/home/claude/.cargo/bin:/home/claude/.local/share/solana/install/active_release/bin:/home/claude/.avm/bin:/home/claude/.local/bin:/home/claude/.npm-globals/bin:/home/claude/.nvm/default-node-bin:<rest of PATH>
/home/claude/.npm-globals
total 8
drwxr-xr-x 2 claude claude 4096 ...  .
drwxr-xr-x ...                       ..
```

Assertions:
- `prefix=/home/claude/.npm-globals` — Dockerfile `ENV` is set.
- The `PATH=...` line contains `/home/claude/.npm-globals/bin` immediately before `/home/claude/.nvm/default-node-bin`.
- `npm config get prefix` (third line printed by the command) prints `/home/claude/.npm-globals`.
- `ls -la /home/claude/.npm-globals` shows the directory exists and is owned by `claude:claude`.

If any of those fail, the Dockerfile changes from Task 1 are wrong — go back and fix.

---

### Task 5: Opt the local config into the new volume and verify drift detection

Existing users (which is what the developer running this plan is) won't pick up the new volume from the template change alone. Apply it via the supported in-CLI command, then verify the existing drift-detection + restart flow reports and applies it correctly.

**Files:**
- None (the change is to the developer's local `configurations.yml`, which is not in git)

- [ ] **Step 1: Add the global mount entry**

```bash
claude-sandbox global mounts add npm-globals:/home/claude/.npm-globals
```

Expected: command exits cleanly (no error).

- [ ] **Step 2: Confirm the entry is in the local config**

```bash
claude-sandbox global mounts list
```

Expected: the output includes `npm-globals:/home/claude/.npm-globals` (alongside any other global mounts you already have).

- [ ] **Step 3: Pick a test project and trigger drift detection**

Pick any existing sandboxed project — `claude-sandbox` itself works — and open it:

```bash
cd /workspace/claude-sandbox
claude-sandbox
```

Expected: because the rendered config now contains a `volume` line the container's snapshot label lacks, drift detection prints something like:

```
Configuration for claude-sandbox has changed since this container was created:
  + volume npm-globals:/home/claude/.npm-globals
Restart the container to apply these changes? [Y/n]
```

Press Enter (or type `y`) to accept the restart. Expected: the container is stopped, removed, recreated, and VS Code reattaches.

If you have no existing sandbox to test against, run `claude-sandbox` to create one, then `claude-sandbox restart $(pwd)` and observe that the recreate succeeds.

- [ ] **Step 4: Confirm the volume is mounted in the new container**

After the restart, inside the container (via the VS Code terminal, or run a one-off `docker exec`):

```bash
mount | grep npm-globals
```

Expected: a line showing the `npm-globals` volume mounted at `/home/claude/.npm-globals`.

Also check:

```bash
ls -la /home/claude/.npm-globals
npm config get prefix
echo $PATH
```

Expected: directory exists and is owned by `claude:claude`; `npm config get prefix` prints `/home/claude/.npm-globals`; `$PATH` contains `/home/claude/.npm-globals/bin`.

---

### Task 6: Smoke-test persistence across `claude-sandbox restart`

The core acceptance test: install a global, restart, verify it's still there.

**Files:**
- None (manual test)

- [ ] **Step 1: Install a test global inside the container**

In the sandboxed project's container (terminal inside the running VS Code session is fine):

```bash
npm install -g cowsay
cowsay "hello from the cache"
which cowsay
ls -la /home/claude/.npm-globals/bin/cowsay
```

Expected:
- `npm install` completes (may print warnings about deprecated packages; non-fatal).
- `cowsay "hello from the cache"` prints an ASCII cow saying the message.
- `which cowsay` prints `/home/claude/.npm-globals/bin/cowsay`.
- `ls -la` shows the binary (typically a symlink to `../lib/node_modules/cowsay/cli.js`).

- [ ] **Step 2: Restart the container**

From the host (outside the container):

```bash
claude-sandbox restart /workspace/claude-sandbox
```

(Substitute the actual project path you used in Task 5.)

Expected: the container is stopped, removed, recreated, and VS Code reattaches. Any in-container shell session ends — that is expected.

- [ ] **Step 3: Verify the binary survived the restart**

Reattach (or open a fresh terminal in the reattached VS Code), then inside the container:

```bash
cowsay "still here"
which cowsay
```

Expected:
- `cowsay "still here"` prints the cow successfully.
- `which cowsay` prints `/home/claude/.npm-globals/bin/cowsay`.

If `cowsay` is not found, the volume is not being mounted into the new container — re-check Task 2's edit and Task 5's `mounts add` step.

---

### Task 7: Verify the cache is shared across project containers

The spec calls for installations made in one project to be available in another. The named volume is global, so this should work for free — but confirm.

**Files:**
- None (manual test)

- [ ] **Step 1: Pick or create a second project**

Use any other directory that is not the test project from Task 5/6. If none exists, make one:

```bash
mkdir -p /tmp/npm-globals-shared-test
cd /tmp/npm-globals-shared-test
git init
```

(`git init` is to make it a tidy project root; not strictly required.)

- [ ] **Step 2: Open it in a sandbox**

```bash
claude-sandbox
```

Expected: a new container is created for this project, VS Code attaches. Because the volume is in the global `volumes` list (via the `mounts add` step), the new container gets the `npm-globals` mount automatically — no drift prompt needed for that entry.

- [ ] **Step 3: Verify the cached binary is available in this project's container**

Inside the second project's container:

```bash
cowsay "shared across projects"
which cowsay
```

Expected:
- `cowsay` prints normally.
- `which cowsay` prints `/home/claude/.npm-globals/bin/cowsay`.

That confirms the toolbox is shared. The implementation is complete.

- [ ] **Step 4: (Optional) Clean up the throwaway test project**

If you used `/tmp/npm-globals-shared-test`, stop and remove its container:

```bash
claude-sandbox stop /tmp/npm-globals-shared-test --rm
rm -rf /tmp/npm-globals-shared-test
```

This keeps `docker ps -a` and the project list tidy. Skip if you want to keep the test sandbox around.

---

## Done

At this point:
- Image carries `NPM_CONFIG_PREFIX` and the extended `PATH`.
- Template declares the `npm-globals` volume for new installs.
- README documents the volume and the upgrade step.
- Manual smoke test confirms install-survives-restart and cross-project sharing.

The branch is ready for PR. Merge into `master` when satisfied.
