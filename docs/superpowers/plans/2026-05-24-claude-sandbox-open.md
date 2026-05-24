# `claude-sandbox open` Subcommand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `claude-sandbox open <target>` subcommand that launches VS Code for any sandbox container by project path or container hash name, with tab completion driven by `docker ps -a`.

**Architecture:** Extract the existing launch flow (git-auth resolution → container status switch → VS Code launch) from the bare `claude-sandbox` command into a `_sandbox_launch <project_path>` helper. Both the bare command and the new `open` subcommand call this helper. `open` first tries `<target>` as a labeled container name; if that fails, it falls back to treating `<target>` as a path. A new fish completion helper emits both the project path and the container hash for every entry in `docker ps -a --filter label=claude-sandbox.project`.

**Tech Stack:** fish shell, Docker CLI, VS Code Remote-Containers

---

### Task 1: Extract `_sandbox_launch` helper

Move the launch flow out of the `claude-sandbox` function body into a standalone helper so both the bare command and `open` can call it. Pure refactor — no behavior change.

**Files:**
- Modify: `functions/claude-sandbox.fish` (lines 379-659 area)

- [ ] **Step 1: Add the `_sandbox_launch` function above `function claude-sandbox`**

Insert this block immediately before `function claude-sandbox` (i.e. before the current line 379):

```fish
function _sandbox_launch
    # Usage: _sandbox_launch <project_path>
    set -l PROJECT_PATH $argv[1]
    set -l PROJECT_NAME (basename $PROJECT_PATH)

    if not docker info > /dev/null 2>&1
        echo "Error: Docker is not running. Please start Docker Desktop first."
        return 1
    end

    # Resolve git auth for this project
    set -l auth_type (_sandbox_config_read_git_auth_type $PROJECT_PATH)
    if test -z "$auth_type"
        _sandbox_git_auth_wizard $PROJECT_PATH $PROJECT_NAME
        or return 1
        set auth_type (_sandbox_config_read_git_auth_type $PROJECT_PATH)
    end

    # Verify credentials file exists if configured
    if test "$auth_type" = ssh; or test "$auth_type" = pat
        set -l creds_path (_sandbox_expand_vars (_sandbox_config_read_git_auth_path $PROJECT_PATH))
        if not test -f $creds_path
            echo "Error: credentials file not found: $creds_path"
            echo "Run 'claude-sandbox git-auth set' to reconfigure."
            return 1
        end
    end

    set -l container_name (_sandbox_container_name $PROJECT_PATH)
    set -l container_status (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)

    switch $container_status
        case running
            echo "Attaching to running sandbox for $PROJECT_NAME..."
        case exited created paused
            echo "Starting sandbox for $PROJECT_NAME..."
            if not docker start $container_name 2>/dev/null
                # Stopped containers can have stale bind-mount paths (e.g. after Docker Desktop
                # restart). The container layer is stateless so it's safe to recreate.
                echo "Start failed (stale container). Recreating..."
                docker rm $container_name
                _sandbox_docker_run $container_name $PROJECT_PATH $PROJECT_NAME
                or begin
                    echo "Error: Failed to start container."
                    return 1
                end
            end
        case restarting
            echo "Container is restarting, please wait and retry."
            return 1
        case removing dead
            echo "Container is being removed or dead; run 'claude-sandbox stop --rm' and retry."
            return 1
        case '*'
            echo "Creating new sandbox for $PROJECT_NAME..."
            _sandbox_docker_run $container_name $PROJECT_PATH $PROJECT_NAME
            or begin
                echo "Error: Failed to create container."
                return 1
            end
    end

    set -l container_json "{\"containerName\":\"/$container_name\"}"
    set -l encoded (printf '%s' $container_json | xxd -p | tr -d '\n')
    code --folder-uri "vscode-remote://attached-container+$encoded/workspace/$PROJECT_NAME"
end
```

- [ ] **Step 2: Replace the inline launch flow in `claude-sandbox` with a call to the helper**

In `function claude-sandbox`, find the `# --- launch flow ---` comment (currently around line 598). Delete from that comment down to the `code --folder-uri ...` line (the last statement of the function before its closing `end`, currently around line 658). Replace the deleted block with:

```fish
    # --- launch flow ---
    _sandbox_launch $PROJECT_PATH
end
```

Make sure exactly one `end` remains, closing `function claude-sandbox`.

- [ ] **Step 3: Reload the function and sanity-check the bare command still works**

`make install` symlinks `functions/claude-sandbox.fish` into `~/.config/fish/functions/`, so edits to the repo file are picked up by a new fish session. To reload in the current session without opening a new shell:

```bash
source ~/.config/fish/functions/claude-sandbox.fish
```

Then, from any existing project folder (one whose container already exists):

```bash
claude-sandbox
```

Expected: the same "Attaching to running sandbox for ..." or "Starting sandbox for ..." output as before, and VS Code opens. No regressions.

- [ ] **Step 4: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "refactor: extract _sandbox_launch helper from bare claude-sandbox command"
```

---

### Task 2: Add the `open` subcommand

Wire the new subcommand into `function claude-sandbox`, including target resolution and help text.

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Update top-level `--help` output**

In the `# --- top-level --help ---` block (around line 384-399), add a new line under `Subcommands:` between the existing `list` and `git-auth` entries:

```fish
        printf "  %-34s%s\n" "list"                  "List all sandbox containers"
        printf "  %-34s%s\n" "open <target>"         "Open VS Code for a sandbox by path or container name"
        printf "  %-34s%s\n" "git-auth <action>"     "Manage per-project git auth"
```

- [ ] **Step 2: Add the `open` subcommand block**

Insert this block immediately before the `# --- launch flow ---` comment (i.e. just before the bare-command path):

```fish
    # --- open subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = open
        if contains -- --help $argv
            echo "Usage: claude-sandbox open <target>"
            echo ""
            echo "  Opens VS Code attached to a sandbox container."
            echo ""
            echo "  <target> may be either:"
            echo "    - A project path (absolute or relative). Creates and starts a"
            echo "      container if one does not exist for that path."
            echo "    - A container name (e.g. claude-sandbox-abc12345) from"
            echo "      'claude-sandbox list'. Must already exist."
            echo ""
            echo "  Tab completion suggests both forms for every existing sandbox."
            return 0
        end
        if test (count $argv) -lt 2
            echo "Usage: claude-sandbox open <target>"
            return 1
        end
        set -l target $argv[2]

        # Try as container name first: must exist AND carry our label.
        set -l labeled_path (docker inspect --format '{{ index .Config.Labels "claude-sandbox.project" }}' $target 2>/dev/null)
        if test -n "$labeled_path"
            _sandbox_launch $labeled_path
            return
        end

        # Fall back to path mode.
        set -l resolved (realpath $target 2>/dev/null)
        if test -z "$resolved"
            echo "Error: '$target' is neither an existing sandbox container nor a valid path."
            return 1
        end
        _sandbox_launch $resolved
        return
    end
```

The `index .Config.Labels` template returns an empty string when the container has no such label (instead of `<no value>`), so the `test -n` check cleanly distinguishes "labeled sandbox container" from "exists but unrelated" or "doesn't exist".

- [ ] **Step 3: Reload and verify the help text**

```bash
source ~/.config/fish/functions/claude-sandbox.fish
claude-sandbox --help
```

Expected: output now includes `open <target>` line under Subcommands.

```bash
claude-sandbox open --help
```

Expected: prints the usage block from Step 2.

- [ ] **Step 4: Verify `open` with a missing argument errors**

```bash
claude-sandbox open
```

Expected: `Usage: claude-sandbox open <target>` and exit status 1.

- [ ] **Step 5: Verify `open` with a container hash works**

Pick any existing container from `claude-sandbox list`, then:

```bash
claude-sandbox open claude-sandbox-<hash-from-list>
```

Expected: same launch output as `cd`-ing into that project and running `claude-sandbox`. VS Code opens for the right project.

- [ ] **Step 6: Verify `open` with a project path works**

```bash
claude-sandbox open /workspace/<some-existing-project-path>
```

Expected: same behavior. Also try a relative path from somewhere else:

```bash
cd /tmp && claude-sandbox open ~/some/project
```

Expected: `realpath` resolves the `~` and the project opens.

- [ ] **Step 7: Verify `open` with an invalid target errors clearly**

```bash
claude-sandbox open /no/such/path
claude-sandbox open claude-sandbox-deadbeef
```

Both expected:
```
Error: '<target>' is neither an existing sandbox container nor a valid path.
```
Exit status 1.

- [ ] **Step 8: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: add claude-sandbox open subcommand"
```

---

### Task 3: Add tab completion for `open`

Register `open` in the top-level completion list and add a target-completion source that pulls from `docker ps -a`.

**Files:**
- Modify: `completions/claude-sandbox.fish`

- [ ] **Step 1: Add `open` to the `$subcommands` list**

Change line 3:

```fish
set -l subcommands stop list git-auth mounts global
```

to:

```fish
set -l subcommands stop list open git-auth mounts global
```

- [ ] **Step 2: Add the top-level completion entry for `open`**

After the existing `-a list` block (around lines 15-17), insert:

```fish
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a open   -d 'Open VS Code for a sandbox by path or container name'
```

- [ ] **Step 3: Add the target-completion helper and rules**

After the existing `# list` block (around lines 36-39), append:

```fish
# open: completion source draws from existing sandbox containers
function __claude_sandbox_open_targets
    docker ps -a --filter "label=claude-sandbox.project" \
        --format '{{.Names}}\t{{.Label "claude-sandbox.project"}}\t{{.Status}}' 2>/dev/null \
        | while read -l line
            set -l parts (string split \t -- $line)
            set -l name $parts[1]
            set -l path $parts[2]
            set -l status $parts[3]
            printf '%s\t%s\n' $path $status
            printf '%s\t%s\n' $name "$path ($status)"
        end
end

complete -c claude-sandbox -f \
    -n "__fish_seen_subcommand_from open" \
    -a '(__claude_sandbox_open_targets)'

complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from open" \
    -l help -d 'Show usage'
```

`string split \t` is required because fish's `read` splits on whitespace by default, which would break multi-word docker statuses like `Up 2 hours`.

- [ ] **Step 4: Reload completions and verify**

`make install` symlinks `completions/claude-sandbox.fish` into `~/.config/fish/completions/`. To reload in the current session:

```bash
source ~/.config/fish/completions/claude-sandbox.fish
```

Then in an interactive fish session:

```
claude-sandbox <TAB>
```

Expected: `open` appears in the candidate list with the description "Open VS Code for a sandbox by path or container name".

```
claude-sandbox open <TAB>
```

Expected: one entry per existing container's project path (described by docker status), plus one entry per container hash name (described by `path (status)`). No filesystem completion (the `-f` flag suppresses it).

- [ ] **Step 5: Verify completion handles statuses with spaces**

Start at least one container so its status reads like `Up 5 minutes`, then re-run:

```
claude-sandbox open <TAB>
```

Expected: the description for that entry shows the full status (`Up 5 minutes`), not just `Up`.

- [ ] **Step 6: Commit**

```bash
git add completions/claude-sandbox.fish
git commit -m "feat: tab completion for claude-sandbox open"
```

---

### Task 4: README update

Document the new subcommand in the quick reference section.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Find the existing quick reference block**

Look for the section starting with `## Quick reference` containing:

```
claude-sandbox --help
claude-sandbox global --help
```

- [ ] **Step 2: Mention the new subcommand**

Add a sentence after the quick-reference code block (or wherever subcommands are listed) noting:

> Use `claude-sandbox open <path-or-container>` from anywhere to attach VS Code to a sandbox. Tab-completion lists every existing container's path and hash.

Keep the addition short — the project's README style is terse.

- [ ] **Step 3: Verify the doc renders sensibly**

Read the README top to bottom and confirm the new line fits the surrounding style.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: mention claude-sandbox open in quick reference"
```

---

### Task 5: End-to-end smoke test

Verify the whole feature from a fresh shell, exercising every documented behavior.

- [ ] **Step 1: Open a fresh terminal so all functions/completions reload**

```bash
exec fish
```

- [ ] **Step 2: List existing sandboxes**

```bash
claude-sandbox list
```

Expected: at least one container row. Note one of its names and its labeled path.

- [ ] **Step 3: Open by container name**

```bash
claude-sandbox open <one-container-name-from-list>
```

Expected: VS Code window opens attached to that container.

- [ ] **Step 4: Open by project path**

```bash
claude-sandbox open <project-path-from-list>
```

Expected: re-attaches to the same container (no new container created — the path hashes to the same name).

- [ ] **Step 5: Open a brand-new path (auth wizard fires)**

Create a throwaway directory the sandbox has never seen:

```bash
mkdir -p /tmp/claude-sandbox-open-smoke && cd / && claude-sandbox open /tmp/claude-sandbox-open-smoke
```

Expected: git-auth wizard runs, container is created, VS Code opens. After it works, tear down:

```bash
claude-sandbox open /tmp/claude-sandbox-open-smoke   # already configured; should attach silently
# In a different terminal:
cd /tmp/claude-sandbox-open-smoke && claude-sandbox stop --rm
rm -rf /tmp/claude-sandbox-open-smoke
```

- [ ] **Step 6: Tab completion check**

In interactive fish:

```
claude-sandbox open <TAB>
```

Expected: container paths and hashes shown with status descriptions, no filesystem entries.

- [ ] **Step 7: All clear — no commit needed**

If everything passes, the feature is complete. If anything failed, fix the relevant earlier task and re-run.
