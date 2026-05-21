# Global Workspace Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `global:` + `projects:` schema to `configurations.yml` so always-on mounts (`.gitconfig`, `skills/`, `rules/`) are explicit and version-controlled, and per-project mounts append to them.

**Architecture:** Migrate `configurations.yml` from a flat schema (project paths as top-level keys) to a structured schema with `global.mounts` and `projects.<path>`. The fish function gains a `_sandbox_migrate_to_nested` auto-migration and a `global` subcommand mirroring the existing `mounts` subcommand. `_sandbox_generate_override` drops its hardcoded `.gitconfig` line and builds volumes from global + per-project mounts in that order.

**Tech Stack:** fish shell, yq (jq-compatible YAML processor), Docker Compose

---

### Task 1: Add `skills/` and `rules/` directories to the repo

**Files:**
- Create: `skills/.gitkeep`
- Create: `rules/.gitkeep`

- [ ] **Step 1: Create the directories and placeholder files**

```bash
touch /home/lhvubtqn/.claude-sandbox/skills/.gitkeep
touch /home/lhvubtqn/.claude-sandbox/rules/.gitkeep
```

- [ ] **Step 2: Verify they exist**

```bash
ls /home/lhvubtqn/.claude-sandbox/skills/
ls /home/lhvubtqn/.claude-sandbox/rules/
```

Expected: `.gitkeep` listed in each.

- [ ] **Step 3: Commit**

```bash
git -C ~/.claude-sandbox add skills/.gitkeep rules/.gitkeep
git -C ~/.claude-sandbox commit -m "feat: add skills/ and rules/ dirs for global claude mounts"
```

---

### Task 2: Add schema migration and update all project-scoped yq paths

All project data moves from `.[$p]` to `.projects[$p]`. The migration must be wired into the launch flow at the same commit so the function is never in a broken intermediate state.

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Back up the current configurations.yml**

```bash
cp ~/.claude-sandbox/configurations.yml ~/.claude-sandbox/configurations.yml.bak
```

- [ ] **Step 2: Verify the migration yq expression against the backup**

Run this against the existing flat file to confirm it produces the right output before touching any code:

```bash
yq -y '{global: {mounts: ["~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro"]}, projects: .}' \
  ~/.claude-sandbox/configurations.yml
```

Expected output shape:
```yaml
global:
  mounts:
    - ~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
projects:
  /home/lhvubtqn/some-project:
    credentials:
      type: ssh
      keyPath: /home/lhvubtqn/.ssh/id_ed25519_some-project
    mounts: []
```

- [ ] **Step 3: Add `_sandbox_migrate_to_nested` after `_sandbox_migrate_from_json`**

In `functions/claude-sandbox.fish`, add this function immediately after `_sandbox_migrate_from_json`:

```fish
function _sandbox_migrate_to_nested
    # Migrate flat schema (project paths as top-level keys) to global/projects schema.
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l has_global (yq -r 'if .global != null then "yes" else "no" end' $f 2>/dev/null)
    set -l has_projects (yq -r 'if .projects != null then "yes" else "no" end' $f 2>/dev/null)
    if test "$has_global" = yes; or test "$has_projects" = yes
        return
    end
    echo "Migrating configurations.yml to global/projects schema..."
    set -l tmp (mktemp)
    yq -y '{global: {mounts: ["~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro"]}, projects: .}' \
        $f > $tmp
    and mv $tmp $f
    and echo "Migration complete."
end
```

- [ ] **Step 4: Wire the migration into the launch flow**

In the `claude-sandbox` function body, find the block that calls `_sandbox_migrate_from_json` and add the new call directly after it:

```fish
    # Auto-migrate from legacy project-creds.json
    _sandbox_migrate_from_json
    # Migrate flat schema to global/projects schema
    _sandbox_migrate_to_nested
```

- [ ] **Step 5: Update `_sandbox_config_read_creds_type`**

Old:
```fish
    yq -r --arg p $argv[1] '.[$p].credentials.type // empty' $f 2>/dev/null
```
New:
```fish
    yq -r --arg p $argv[1] '.projects[$p].credentials.type // empty' $f 2>/dev/null
```

- [ ] **Step 6: Update `_sandbox_config_read_creds_key`**

Old:
```fish
    yq -r --arg p $argv[1] '.[$p].credentials.keyPath // empty' $f 2>/dev/null
```
New:
```fish
    yq -r --arg p $argv[1] '.projects[$p].credentials.keyPath // empty' $f 2>/dev/null
```

- [ ] **Step 7: Update `_sandbox_config_write_creds_ssh`**

Old:
```fish
    yq -y --arg p $argv[1] --arg k $argv[2] \
        '.[$p].credentials = {"type": "ssh", "keyPath": $k}' $f > $tmp
```
New:
```fish
    yq -y --arg p $argv[1] --arg k $argv[2] \
        '.projects[$p].credentials = {"type": "ssh", "keyPath": $k}' $f > $tmp
```

- [ ] **Step 8: Update `_sandbox_config_write_creds_none`**

Old:
```fish
    yq -y --arg p $argv[1] \
        '.[$p].credentials = {"type": "none"}' $f > $tmp
```
New:
```fish
    yq -y --arg p $argv[1] \
        '.projects[$p].credentials = {"type": "none"}' $f > $tmp
```

- [ ] **Step 9: Update `_sandbox_config_delete`**

Old:
```fish
    yq -y --arg p $argv[1] 'del(.[$p].credentials)' $f > $tmp
```
New:
```fish
    yq -y --arg p $argv[1] 'del(.projects[$p].credentials)' $f > $tmp
```

- [ ] **Step 10: Update `_sandbox_mounts_list`**

Old:
```fish
    yq -r --arg p $argv[1] '.[$p].mounts // [] | .[]' $f 2>/dev/null
```
New:
```fish
    yq -r --arg p $argv[1] '.projects[$p].mounts // [] | .[]' $f 2>/dev/null
```

- [ ] **Step 11: Update `_sandbox_mounts_add`**

Old:
```fish
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.[$p].mounts = ((.[$p].mounts // []) + [$m])' $f > $tmp
```
New:
```fish
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.projects[$p].mounts = ((.projects[$p].mounts // []) + [$m])' $f > $tmp
```

- [ ] **Step 12: Update `_sandbox_mounts_remove` — count check**

Old:
```fish
    set -l count (yq -r --arg p $argv[1] '.[$p].mounts | length' $f 2>/dev/null)
```
New:
```fish
    set -l count (yq -r --arg p $argv[1] '.projects[$p].mounts | length' $f 2>/dev/null)
```

- [ ] **Step 13: Update `_sandbox_mounts_remove` — filter expression**

Old:
```fish
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.[$p].mounts = [(.[$p].mounts // [])[] | select(. != $m)]' $f > $tmp
```
New:
```fish
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.projects[$p].mounts = [(.projects[$p].mounts // [])[] | select(. != $m)]' $f > $tmp
```

- [ ] **Step 14: Update `_sandbox_mounts_clear`**

Old:
```fish
    yq -y --arg p $argv[1] 'del(.[$p].mounts)' $f > $tmp
```
New:
```fish
    yq -y --arg p $argv[1] 'del(.projects[$p].mounts)' $f > $tmp
```

- [ ] **Step 15: Update `creds list` display**

Old:
```fish
                yq -r 'to_entries[] | select(.value.credentials != null) | "\(.key)\n  type: \(.value.credentials.type)" + (if .value.credentials.keyPath then "\n  keyPath: \(.value.credentials.keyPath)" else "" end)' $f
```
New:
```fish
                yq -r '.projects | to_entries[] | select(.value.credentials != null) | "\(.key)\n  type: \(.value.credentials.type)" + (if .value.credentials.keyPath then "\n  keyPath: \(.value.credentials.keyPath)" else "" end)' $f
```

- [ ] **Step 16: Source the updated function and verify migration runs**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
_sandbox_migrate_to_nested
cat ~/.claude-sandbox/configurations.yml
```

Expected: file now has `global:` and `projects:` top-level keys, with existing project data nested under `projects:`.

- [ ] **Step 17: Verify migration is idempotent**

```fish
_sandbox_migrate_to_nested
cat ~/.claude-sandbox/configurations.yml
```

Expected: no "Migrating…" output; file unchanged.

- [ ] **Step 18: Verify an existing credential still reads correctly**

```fish
_sandbox_config_read_creds_type /home/lhvubtqn/workdir/mattle-fun/godew-valley
```

Expected: `ssh`

- [ ] **Step 19: Verify an existing per-project mount still lists correctly**

```fish
_sandbox_mounts_list /home/lhvubtqn/workdir/mattle-fun/godew-valley
```

Expected: `/home/lhvubtqn/.local/bin/godot_v4.6.2:/home/claude/.local/bin/godot`

- [ ] **Step 20: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: migrate configurations.yml to global/projects schema"
```

---

### Task 3: Add global mount helper functions

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Add four global mount helpers after `_sandbox_mounts_clear`**

Insert these four functions in `functions/claude-sandbox.fish` immediately after `_sandbox_mounts_clear`:

```fish
function _sandbox_global_mounts_list
    set -l f (_sandbox_config_file)
    test -f $f; or return
    yq -r '.global.mounts // [] | .[]' $f 2>/dev/null
end

function _sandbox_global_mounts_add
    # Usage: _sandbox_global_mounts_add <mount_spec>
    set -l f (_sandbox_config_file)
    test -f $f; or echo 'global: {}' > $f
    set -l tmp (mktemp)
    yq -y --arg m $argv[1] \
        '.global.mounts = ((.global.mounts // []) + [$m])' $f > $tmp
    and mv $tmp $f
end

function _sandbox_global_mounts_remove
    # Usage: _sandbox_global_mounts_remove <mount_spec>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg m $argv[1] \
        '.global.mounts = [(.global.mounts // [])[] | select(. != $m)]' $f > $tmp
    and mv $tmp $f
end

function _sandbox_global_mounts_clear
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y 'del(.global.mounts)' $f > $tmp
    and mv $tmp $f
end
```

- [ ] **Step 2: Source and verify `_sandbox_global_mounts_list`**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
_sandbox_global_mounts_list
```

Expected (after Task 2 migration):
```
~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
```

- [ ] **Step 3: Verify `_sandbox_global_mounts_add` and `_sandbox_global_mounts_remove`**

```fish
_sandbox_global_mounts_add "~/.claude-sandbox/skills:/home/claude/.claude/skills:ro"
_sandbox_global_mounts_list
```

Expected: two lines — the `.gitconfig` entry plus the new skills entry.

```fish
_sandbox_global_mounts_remove "~/.claude-sandbox/skills:/home/claude/.claude/skills:ro"
_sandbox_global_mounts_list
```

Expected: back to one line (`.gitconfig` only).

- [ ] **Step 4: Add skills and rules entries to global mounts**

```fish
_sandbox_global_mounts_add "~/.claude-sandbox/skills:/home/claude/.claude/skills:ro"
_sandbox_global_mounts_add "~/.claude-sandbox/rules:/home/claude/.claude/rules:ro"
_sandbox_global_mounts_list
```

Expected:
```
~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
~/.claude-sandbox/skills:/home/claude/.claude/skills:ro
~/.claude-sandbox/rules:/home/claude/.claude/rules:ro
```

- [ ] **Step 5: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish configurations.yml
git -C ~/.claude-sandbox commit -m "feat: add global mount helpers and populate default global mounts"
```

---

### Task 4: Update `_sandbox_generate_override` to use global + per-project mounts

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Replace the volumes initializer and loop in `_sandbox_generate_override`**

Find the current `_sandbox_generate_override` function. Replace its entire body with:

```fish
function _sandbox_generate_override
    # Usage: _sandbox_generate_override <project_path> <project_name>
    set -l project_path $argv[1]
    set -l project_name $argv[2]
    set -l out $HOME/.claude-sandbox/docker-compose.override.yml

    set -l volumes \
        "      - $project_path:/workspace/$project_name"

    for m in (_sandbox_global_mounts_list)
        set volumes $volumes "      - "(_sandbox_expand_path $m)
    end

    set -l creds_type (_sandbox_config_read_creds_type $project_path)
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_config_read_creds_key $project_path)
        set volumes $volumes "      - $key_path:/home/claude/.ssh/deploy_key:ro"
    end

    for m in (_sandbox_mounts_list $project_path)
        set volumes $volumes "      - $m"
    end

    printf 'services:\n  claude-sandbox:\n    working_dir: /workspace/%s\n    volumes:\n' \
        $project_name > $out
    for vol in $volumes
        printf '%s\n' $vol >> $out
    end
end
```

- [ ] **Step 2: Source and generate a test override**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
_sandbox_generate_override /home/lhvubtqn/workdir/mattle-fun/godew-valley godew-valley
cat ~/.claude-sandbox/docker-compose.override.yml
```

Expected output:
```yaml
services:
  claude-sandbox:
    working_dir: /workspace/godew-valley
    volumes:
      - /home/lhvubtqn/workdir/mattle-fun/godew-valley:/workspace/godew-valley
      - /home/lhvubtqn/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
      - /home/lhvubtqn/.claude-sandbox/skills:/home/claude/.claude/skills:ro
      - /home/lhvubtqn/.claude-sandbox/rules:/home/claude/.claude/rules:ro
      - /home/lhvubtqn/.local/bin/godot_v4.6.2:/home/claude/.local/bin/godot
```

Verify: `.gitconfig` comes from `_sandbox_global_mounts_list` (expanded), skills and rules follow, then the per-project godot mount.

- [ ] **Step 3: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: drive _sandbox_generate_override from global+project mounts"
```

---

### Task 5: Add `global` subcommand to `claude-sandbox`

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Add the `global` subcommand block**

In the `claude-sandbox` function body, add this block immediately before the existing `if test … = creds` block:

```fish
    # --- global subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = global
        if test (count $argv) -lt 3; or test $argv[2] != mounts
            echo "Usage: claude-sandbox global mounts {add <spec>|remove <spec>|list|clear}"
            return 1
        end
        set -l action $argv[3]
        switch $action
            case add
                if test (count $argv) -lt 4
                    echo "Usage: claude-sandbox global mounts add <source>:<target>[:<options>]"
                    return 1
                end
                _sandbox_global_mounts_add $argv[4]
                echo "Added global mount: $argv[4]"
            case remove
                if test (count $argv) -lt 4
                    echo "Usage: claude-sandbox global mounts remove <source>:<target>[:<options>]"
                    return 1
                end
                _sandbox_global_mounts_remove $argv[4]
                echo "Removed global mount: $argv[4]"
            case list
                set -l mounts (_sandbox_global_mounts_list)
                if test (count $mounts) -eq 0
                    echo "No global mounts configured"
                else
                    for m in $mounts
                        echo $m
                    end
                end
            case clear
                _sandbox_global_mounts_clear
                echo "Cleared all global mounts"
            case '*'
                echo "Usage: claude-sandbox global mounts {add <spec>|remove <spec>|list|clear}"
                return 1
        end
        return
    end
```

- [ ] **Step 2: Source and verify `global mounts list`**

```fish
source ~/.claude-sandbox/functions/claude-sandbox.fish
claude-sandbox global mounts list
```

Expected:
```
~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
~/.claude-sandbox/skills:/home/claude/.claude/skills:ro
~/.claude-sandbox/rules:/home/claude/.claude/rules:ro
```

- [ ] **Step 3: Verify `global mounts add` and `global mounts remove`**

```fish
claude-sandbox global mounts add "/tmp/test:/tmp/test:ro"
claude-sandbox global mounts list
```

Expected: four lines including `/tmp/test:/tmp/test:ro`.

```fish
claude-sandbox global mounts remove "/tmp/test:/tmp/test:ro"
claude-sandbox global mounts list
```

Expected: back to three lines.

- [ ] **Step 4: Verify bad usage prints usage string**

```fish
claude-sandbox global
```

Expected: `Usage: claude-sandbox global mounts {add <spec>|remove <spec>|list|clear}` and non-zero exit.

- [ ] **Step 5: Commit**

```bash
git -C ~/.claude-sandbox add functions/claude-sandbox.fish
git -C ~/.claude-sandbox commit -m "feat: add claude-sandbox global mounts subcommand"
```

---

### Task 6: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add `skills/` and `rules/` rows to the Volume map table**

Find the table rows for `.gitconfig (bind, ro)` and add two new rows after it:

```markdown
| `~/.claude-sandbox/skills/` (bind, ro) | `/home/claude/.claude/skills/` | Custom Claude Code skills, version-controlled in this repo |
| `~/.claude-sandbox/rules/` (bind, ro) | `/home/claude/.claude/rules/` | Global Claude Code rules, version-controlled in this repo |
```

- [ ] **Step 2: Add a `Global workspace` section**

Add a new `## Global workspace` section after the `## Git credentials` section:

```markdown
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
```

- [ ] **Step 3: Add a note to Setup step 3 in the README**

Find the Setup section step that says "Install the fish function" and append this sentence to it:

```markdown
On first launch, `configurations.yml` is auto-initialized with default global mounts (`.gitconfig`, `skills/`, `rules/`).
```

- [ ] **Step 4: Verify the README renders cleanly**

```bash
cat ~/.claude-sandbox/README.md | grep -A 5 "Global workspace"
cat ~/.claude-sandbox/README.md | grep -A 3 "auto-initialized"
```

Expected: both grep results show content.

- [ ] **Step 5: Commit**

```bash
git -C ~/.claude-sandbox add README.md
git -C ~/.claude-sandbox commit -m "docs: document global workspace mounts and skills/rules dirs"
```

---

### Task 7: Install updated fish function and end-to-end smoke test

- [ ] **Step 1: Install the updated function**

```bash
cp ~/.claude-sandbox/functions/claude-sandbox.fish ~/.config/fish/functions/claude-sandbox.fish
```

- [ ] **Step 2: Open a new fish shell and verify function loads**

```fish
type claude-sandbox
```

Expected: shows the function definition (not "not found").

- [ ] **Step 3: Verify `configurations.yml` has the correct shape**

```bash
cat ~/.claude-sandbox/configurations.yml
```

Expected:
```yaml
global:
  mounts:
    - ~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro
    - ~/.claude-sandbox/skills:/home/claude/.claude/skills:ro
    - ~/.claude-sandbox/rules:/home/claude/.claude/rules:ro
projects:
  /home/lhvubtqn/...:
    ...
```

- [ ] **Step 4: Run a full launch dry-run (generate override, don't start Docker)**

```fish
cd ~/workdir/mattle-fun/godew-valley
_sandbox_generate_override (pwd) (basename (pwd))
cat ~/.claude-sandbox/docker-compose.override.yml
```

Expected: override file contains workspace mount, all three global mounts (paths expanded), the SSH key mount, and the project-specific godot mount — in that order.
