# Config Bootstrap and Variable Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-create `configurations.yml` from `configurations.yml.template` on first use (with variables expanded), add it to `.gitignore`, and rename `REPO_DIR` to `WORKDIR` in the Makefile.

**Architecture:** All three changes are mechanical. The bootstrap logic lives entirely inside `_sandbox_config_file` — already called by every config operation — so no other function needs to change. The sed expansion at copy time means the live config always has absolute paths.

**Tech Stack:** fish shell, sed, yq, GNU make

---

### Task 1: Rename REPO_DIR → WORKDIR in Makefile

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Apply the rename**

Open `Makefile`. It currently reads:

```makefile
REPO_DIR = $(CURDIR)

.PHONY: build build-no-cache install

build:
	docker build -t claude-sandbox $(REPO_DIR)

build-no-cache:
	docker build --no-cache -t claude-sandbox $(REPO_DIR)

install:
	mkdir -p $(HOME)/.config/fish/functions $(HOME)/.config/fish/completions
	ln -sf $(REPO_DIR)/functions/claude-sandbox.fish $(HOME)/.config/fish/functions/claude-sandbox.fish
	ln -sf $(REPO_DIR)/completions/claude-sandbox.fish $(HOME)/.config/fish/completions/claude-sandbox.fish
```

Replace every occurrence of `REPO_DIR` with `WORKDIR`:

```makefile
WORKDIR = $(CURDIR)

.PHONY: build build-no-cache install

build:
	docker build -t claude-sandbox $(WORKDIR)

build-no-cache:
	docker build --no-cache -t claude-sandbox $(WORKDIR)

install:
	mkdir -p $(HOME)/.config/fish/functions $(HOME)/.config/fish/completions
	ln -sf $(WORKDIR)/functions/claude-sandbox.fish $(HOME)/.config/fish/functions/claude-sandbox.fish
	ln -sf $(WORKDIR)/completions/claude-sandbox.fish $(HOME)/.config/fish/completions/claude-sandbox.fish
```

- [ ] **Step 2: Verify no REPO_DIR references remain**

```bash
grep -n REPO_DIR Makefile
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: rename REPO_DIR to WORKDIR in Makefile"
```

---

### Task 2: Add configurations.yml to .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add the entry**

Append `configurations.yml` to `.gitignore`. The file currently contains:

```
.env
project-creds.json
.claude/settings.local.json
```

It should become:

```
.env
project-creds.json
.claude/settings.local.json
configurations.yml
```

- [ ] **Step 2: Verify configurations.yml is now ignored**

```bash
git status
```

Expected: `configurations.yml` does not appear in the output (it should be ignored). If it was previously tracked, it will still show — but since it's untracked right now, it should simply disappear from `git status` output.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore configurations.yml (user-specific, generated from template)"
```

---

### Task 3: Bootstrap configurations.yml from template in _sandbox_config_file

**Files:**
- Modify: `functions/claude-sandbox.fish` — `_sandbox_config_file` function (lines 1–4)

- [ ] **Step 1: Replace _sandbox_config_file**

The current function:

```fish
function _sandbox_config_file
    set -l repo_dir (dirname (dirname (realpath (status filename))))
    echo $repo_dir/configurations.yml
end
```

Replace it with:

```fish
function _sandbox_config_file
    set -l repo_dir (dirname (dirname (realpath (status filename))))
    set -l config $repo_dir/configurations.yml
    if not test -f $config
        set -l template $repo_dir/configurations.yml.template
        if test -f $template
            sed -e "s|\${WORKDIR}|$repo_dir|g" \
                -e "s|\${HOME}|$HOME|g" \
                -e "s|~/|$HOME/|g" \
                $template > $config
        end
    end
    echo $config
end
```

- [ ] **Step 2: Reload the fish function**

```bash
source ~/.config/fish/functions/claude-sandbox.fish
```

- [ ] **Step 3: Verify bootstrap works**

Temporarily move `configurations.yml` aside so the bootstrap triggers:

```bash
mv /home/lhvubtqn/github/claude-sandbox/configurations.yml /home/lhvubtqn/github/claude-sandbox/configurations.yml.bak
```

Run any config-reading subcommand (from any directory):

```bash
claude-sandbox list
```

Check that `configurations.yml` was created and variables were expanded:

```bash
cat /home/lhvubtqn/github/claude-sandbox/configurations.yml
```

Expected: the file exists and contains absolute paths — `${WORKDIR}` replaced with the actual repo path, `${HOME}` replaced with `/home/lhvubtqn`, and `~/` expanded. No literal `${WORKDIR}`, `${HOME}`, or `~/` should appear.

- [ ] **Step 4: Restore the real configurations.yml**

```bash
mv /home/lhvubtqn/github/claude-sandbox/configurations.yml.bak /home/lhvubtqn/github/claude-sandbox/configurations.yml
```

- [ ] **Step 5: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: auto-create configurations.yml from template on first use, expanding \${WORKDIR}, \${HOME}, and ~"
```
