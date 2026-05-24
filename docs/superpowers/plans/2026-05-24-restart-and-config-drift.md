# `claude-sandbox restart` + Config-Drift Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `claude-sandbox restart <target>` subcommand that recreates a container with the current config and reattaches VS Code, and make the reopen flow detect config drift, show what changed, and offer to restart.

**Architecture:** A single helper `_sandbox_render_config <path>` renders the effective container config (image, volumes, security_opt, extra_hosts, git-auth) as canonical sorted `category<TAB>value` lines — the one definition of "what counts as config." `_sandbox_docker_run` stores that snapshot base64-encoded in a `claude-sandbox.config-snapshot` container label. `_sandbox_config_diff <path> <container>` decodes the label, re-renders, and prints `+`/`- ` change lines. The launch flow (`_sandbox_launch`) gains a drift check that prompts (default Yes) to recreate. Shared helpers `_sandbox_preflight`, `_sandbox_recreate`, and `_sandbox_attach` are extracted so `restart`, the drift branch, and `_sandbox_launch` share one code path. `restart` resolves `<target>` exactly like `open` (container-name first, then path).

**Tech Stack:** fish shell, Docker CLI, `yq`, `base64`/`comm`/`sort`, VS Code Remote-Containers.

**Testing note:** This project has no automated test harness; verification follows the existing convention (reload the function/completion file, run the command, observe output). All edits target `functions/claude-sandbox.fish` and `completions/claude-sandbox.fish`, which `make install` symlinks into `~/.config/fish/`.

---

### Task 1: Add `_sandbox_render_config` helper

Render the effective container config as canonical, sorted, tab-delimited lines. This is the single source of "what counts as config" and must mirror exactly what `_sandbox_docker_run` applies (`functions/claude-sandbox.fish:180-244`).

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Add the `_sandbox_render_config` function**

Insert this block immediately **after** the `_sandbox_container_name` function (currently ends at line 178, just before `function _sandbox_docker_run`):

```fish
function _sandbox_render_config
    # Usage: _sandbox_render_config <project_path>
    # Emits a canonical, sorted snapshot of the effective container config as
    # tab-delimited "category<TAB>value" lines. Single source of truth for drift
    # detection. Must mirror the args _sandbox_docker_run actually applies.
    set -l f (_sandbox_config_file)
    set -l p $argv[1]

    # image (single value; project overrides global; default claude-sandbox)
    set -l image (yq -r --arg p $p \
        '(.projects[$p].container.image // .global.container.image // "claude-sandbox")' $f 2>/dev/null)
    printf 'image\t%s\n' $image

    # volumes: global then project, sorted
    for vol in (yq -r --arg p $p \
        '((.global.container.volumes // []) + (.projects[$p].container.volumes // [])) | .[]' $f 2>/dev/null | sort)
        printf 'volume\t%s\n' $vol
    end

    # security_opt: global then project, sorted
    for opt in (yq -r --arg p $p \
        '((.global.container.security_opt // []) + (.projects[$p].container.security_opt // [])) | .[]' $f 2>/dev/null | sort)
        printf 'security_opt\t%s\n' $opt
    end

    # extra_hosts: global then project, sorted
    for host in (yq -r --arg p $p \
        '((.global.container.extra_hosts // []) + (.projects[$p].container.extra_hosts // [])) | .[]' $f 2>/dev/null | sort)
        printf 'extra_host\t%s\n' $host
    end

    # git auth: emit each line only when _sandbox_docker_run would apply the arg
    set -l auth_type (_sandbox_config_read_git_auth_type $p)
    printf 'git_auth_type\t%s\n' $auth_type
    if test "$auth_type" = ssh; or test "$auth_type" = pat
        printf 'git_auth_path\t%s\n' (_sandbox_config_read_git_auth_path $p)
    end
    if test "$auth_type" = ssh
        if test (_sandbox_config_read_git_auth_prefer_ssh $p) = true
            printf 'git_prefer_ssh\t%s\n' true
        end
    end
    set -l id_name (_sandbox_config_read_git_auth_identity_name $p)
    set -l id_email (_sandbox_config_read_git_auth_identity_email $p)
    if test -n "$id_name"
        printf 'git_identity_name\t%s\n' $id_name
    end
    if test -n "$id_email"
        printf 'git_identity_email\t%s\n' $id_email
    end
end
```

Note: `printf` emits a real tab via `\t`. Volume/host specs come from `yq` command substitution (variables), so fish performs **no** tilde/`${VAR}` expansion on them — they are stored raw, exactly as written in `configurations.yml`.

- [ ] **Step 2: Reload and render the current project's config**

```bash
source ~/.config/fish/functions/claude-sandbox.fish
_sandbox_render_config (pwd)
```

Expected: tab-separated lines, e.g.:

```
image	claude-sandbox
git_auth_type	ssh
git_auth_path	~/.ssh/id_ed25519_foo
git_prefer_ssh	true
git_identity_name	Your Name
git_identity_email	you@example.com
```

(Exact lines depend on your config. A project with extra mounts also shows `volume<TAB>...` lines.) Confirm there are no empty-valued git lines for auth types that don't apply.

- [ ] **Step 3: Verify rendering is stable (no spurious diff on re-render)**

```bash
diff (_sandbox_render_config (pwd) | psub) (_sandbox_render_config (pwd) | psub) && echo "STABLE"
```

Expected: `STABLE` (two renders are byte-identical).

- [ ] **Step 4: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: add _sandbox_render_config config-snapshot helper"
```

---

### Task 2: Store the config snapshot as a container label

Have `_sandbox_docker_run` stamp the rendered snapshot onto every container it creates.

**Files:**
- Modify: `functions/claude-sandbox.fish:236-241` (the tail of `_sandbox_docker_run`)

- [ ] **Step 1: Add the label just before the `docker run` call**

In `_sandbox_docker_run`, find this block (currently lines 236-241):

```fish
    # Project workspace bind mount
    set args $args -v "$project_path:/workspace/$project_name"

    set args $args \
        --workdir /workspace/$project_name \
        --entrypoint /entrypoint.sh

    docker run $args $image sleep infinity
```

Insert the snapshot label between the workspace bind mount and the `--workdir` block, so it reads:

```fish
    # Project workspace bind mount
    set args $args -v "$project_path:/workspace/$project_name"

    # Config snapshot label for drift detection
    set -l config_snapshot (_sandbox_render_config $project_path | base64 | tr -d '\n')
    set args $args --label "claude-sandbox.config-snapshot=$config_snapshot"

    set args $args \
        --workdir /workspace/$project_name \
        --entrypoint /entrypoint.sh

    docker run $args $image sleep infinity
```

`base64 | tr -d '\n'` keeps the multi-line snapshot a single safe label value (same pattern as the `xxd -p | tr -d '\n'` VS Code URI encoding).

- [ ] **Step 2: Reload, recreate a throwaway container, and confirm the label exists**

```bash
source ~/.config/fish/functions/claude-sandbox.fish
mkdir -p /tmp/cs-drift-smoke
_sandbox_docker_run (_sandbox_container_name /tmp/cs-drift-smoke) /tmp/cs-drift-smoke cs-drift-smoke
```

If a git-auth type is required for that path and none is set, this may fail because no auth is configured for the throwaway path — in that case set one first with `cd /tmp/cs-drift-smoke && claude-sandbox git-auth set` (choose Skip), then re-run the `_sandbox_docker_run` line.

Then inspect the label:

```bash
docker inspect --format '{{ index .Config.Labels "claude-sandbox.config-snapshot" }}' (_sandbox_container_name /tmp/cs-drift-smoke) | base64 -d
```

Expected: the decoded output matches `_sandbox_render_config /tmp/cs-drift-smoke`.

- [ ] **Step 3: Tear down the throwaway container**

```bash
docker rm -f (_sandbox_container_name /tmp/cs-drift-smoke)
rm -rf /tmp/cs-drift-smoke
```

- [ ] **Step 4: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: stamp config-snapshot label on created containers"
```

---

### Task 3: Add `_sandbox_config_diff` helper

Compare a container's stored snapshot against the freshly-rendered config and print human-readable change lines.

**Files:**
- Modify: `functions/claude-sandbox.fish`

- [ ] **Step 1: Add the `_sandbox_config_diff` function**

Insert immediately **after** the `_sandbox_render_config` function added in Task 1:

```fish
function _sandbox_config_diff
    # Usage: _sandbox_config_diff <project_path> <container_name>
    # Prints "  - category value" / "  + category value" lines for config changes.
    # Returns 1 if there is any drift, 0 if identical.
    set -l project_path $argv[1]
    set -l container_name $argv[2]

    set -l before (mktemp)
    set -l after (mktemp)

    # Stored snapshot (empty file if the label is absent — e.g. pre-feature containers)
    docker inspect --format '{{ index .Config.Labels "claude-sandbox.config-snapshot" }}' $container_name 2>/dev/null \
        | base64 -d 2>/dev/null | sort > $before
    _sandbox_render_config $project_path | sort > $after

    set -l drift 0
    # Removed: present at creation, absent now
    for line in (comm -23 $before $after)
        printf '  - %s\n' (string replace \t ' ' -- $line)
        set drift 1
    end
    # Added: present now, absent at creation
    for line in (comm -13 $before $after)
        printf '  + %s\n' (string replace \t ' ' -- $line)
        set drift 1
    end

    rm -f $before $after
    return $drift
end
```

`comm` requires sorted inputs (we `sort` both). A changed single-valued field such as `image` shows as a `-` of the old value plus a `+` of the new. `string replace \t ' '` swaps the single tab for a space for display.

- [ ] **Step 2: Reload and verify "no drift" on a matching container**

Recreate the throwaway container so its label matches current config:

```bash
source ~/.config/fish/functions/claude-sandbox.fish
mkdir -p /tmp/cs-drift-smoke
docker rm -f (_sandbox_container_name /tmp/cs-drift-smoke) 2>/dev/null
cd /tmp/cs-drift-smoke && claude-sandbox git-auth set   # choose Skip if prompted
_sandbox_docker_run (_sandbox_container_name /tmp/cs-drift-smoke) /tmp/cs-drift-smoke cs-drift-smoke
_sandbox_config_diff /tmp/cs-drift-smoke (_sandbox_container_name /tmp/cs-drift-smoke); echo "rc=$status"
```

Expected: no output and `rc=0` (snapshot equals current render).

- [ ] **Step 3: Verify drift is detected and described after a config change**

Add a project mount for the throwaway path, then re-diff **without** recreating:

```bash
cd /tmp/cs-drift-smoke && claude-sandbox mounts add '~/cs-data:/data'
_sandbox_config_diff /tmp/cs-drift-smoke (_sandbox_container_name /tmp/cs-drift-smoke); echo "rc=$status"
```

Expected:

```
  + volume ~/cs-data:/data
rc=1
```

- [ ] **Step 4: Verify a label-less (pre-feature) container reports drift**

```bash
docker rm -f (_sandbox_container_name /tmp/cs-drift-smoke) 2>/dev/null
# Create a container WITHOUT the snapshot label to simulate a pre-feature container:
docker run -d --name (_sandbox_container_name /tmp/cs-drift-smoke) \
    --label "claude-sandbox.project=/tmp/cs-drift-smoke" claude-sandbox sleep infinity
_sandbox_config_diff /tmp/cs-drift-smoke (_sandbox_container_name /tmp/cs-drift-smoke); echo "rc=$status"
```

Expected: every current config line printed as `+ ...` (at minimum `+ image claude-sandbox` and `+ git_auth_type ...`), and `rc=1`.

- [ ] **Step 5: Tear down**

```bash
docker rm -f (_sandbox_container_name /tmp/cs-drift-smoke) 2>/dev/null
cd /tmp/cs-drift-smoke && claude-sandbox mounts clear
cd / && rm -rf /tmp/cs-drift-smoke
```

- [ ] **Step 6: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: add _sandbox_config_diff drift-detection helper"
```

---

### Task 4: Extract `_sandbox_preflight`, `_sandbox_recreate`, `_sandbox_attach` (pure refactor)

Pull the shared pieces out of `_sandbox_launch` so `restart` and the drift branch can reuse them. **No behavior change.**

**Files:**
- Modify: `functions/claude-sandbox.fish:379-444` (the current `_sandbox_launch`)

- [ ] **Step 1: Add the three helpers above `_sandbox_launch`**

Insert this block immediately **before** `function _sandbox_launch` (currently line 379):

```fish
function _sandbox_preflight
    # Usage: _sandbox_preflight <project_path>
    # Docker-running check, git-auth resolution (runs the wizard if unset),
    # and credentials-file verification. Returns non-zero on any failure.
    set -l project_path $argv[1]
    set -l project_name (basename $project_path)

    if not docker info > /dev/null 2>&1
        echo "Error: Docker is not running. Please start Docker Desktop first."
        return 1
    end

    set -l auth_type (_sandbox_config_read_git_auth_type $project_path)
    if test -z "$auth_type"
        _sandbox_git_auth_wizard $project_path $project_name
        or return 1
        set auth_type (_sandbox_config_read_git_auth_type $project_path)
    end

    if test "$auth_type" = ssh; or test "$auth_type" = pat
        set -l creds_path (_sandbox_expand_vars (_sandbox_config_read_git_auth_path $project_path))
        if not test -f $creds_path
            echo "Error: credentials file not found: $creds_path"
            echo "Run 'claude-sandbox git-auth set' to reconfigure."
            return 1
        end
    end
end

function _sandbox_attach
    # Usage: _sandbox_attach <container_name> <project_name>
    set -l container_name $argv[1]
    set -l project_name $argv[2]
    set -l container_json "{\"containerName\":\"/$container_name\"}"
    set -l encoded (printf '%s' $container_json | xxd -p | tr -d '\n')
    code --folder-uri "vscode-remote://attached-container+$encoded/workspace/$project_name"
end

function _sandbox_recreate
    # Usage: _sandbox_recreate <container_name> <project_path> <project_name>
    # Stops (if running) and removes (if present) any existing container, then
    # creates a fresh one with current config. Returns _sandbox_docker_run's status.
    set -l container_name $argv[1]
    set -l project_path $argv[2]
    set -l project_name $argv[3]

    set -l st (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)
    if test "$st" = running; or test "$st" = paused; or test "$st" = restarting
        docker stop $container_name > /dev/null
    end
    if test -n "$st"
        docker rm $container_name > /dev/null
    end
    _sandbox_docker_run $container_name $project_path $project_name
end
```

- [ ] **Step 2: Rewrite `_sandbox_launch` to use the helpers**

Replace the entire current `_sandbox_launch` function (lines 379-444) with:

```fish
function _sandbox_launch
    # Usage: _sandbox_launch <project_path>
    set -l PROJECT_PATH $argv[1]
    set -l PROJECT_NAME (basename $PROJECT_PATH)

    _sandbox_preflight $PROJECT_PATH; or return 1

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
                _sandbox_recreate $container_name $PROJECT_PATH $PROJECT_NAME
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

    _sandbox_attach $container_name $PROJECT_NAME
end
```

This is identical behavior to before: the only changes are calling `_sandbox_preflight` for the preamble, `_sandbox_recreate` in place of the inline `docker rm` + `_sandbox_docker_run` stale-recovery, and `_sandbox_attach` for the trailing VS Code launch.

- [ ] **Step 3: Reload and confirm no regression on the bare command**

```bash
source ~/.config/fish/functions/claude-sandbox.fish
```

From a project folder whose container already exists:

```bash
claude-sandbox
```

Expected: same `Attaching to running sandbox for ...` / `Starting sandbox for ...` output as before, and VS Code opens. No behavior change.

- [ ] **Step 4: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "refactor: extract _sandbox_preflight, _sandbox_recreate, _sandbox_attach helpers"
```

---

### Task 5: Add the drift check + restart prompt to `_sandbox_launch`

On reopen of an existing container, show the diff and prompt (default Yes) to recreate.

**Files:**
- Modify: `functions/claude-sandbox.fish` (the `_sandbox_launch` from Task 4)

- [ ] **Step 1: Insert the drift check between container-status lookup and the `switch`**

In `_sandbox_launch`, after the line:

```fish
    set -l container_status (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)
```

and **before** `switch $container_status`, insert:

```fish
    # Detect config drift for a reusable existing container and offer to restart.
    # Scoped to states the launch flow would otherwise reuse; transient states
    # (restarting/removing/dead) keep their dedicated handling in the switch below.
    if contains -- "$container_status" running exited created paused
        set -l drift_lines (_sandbox_config_diff $PROJECT_PATH $container_name)
        if test (count $drift_lines) -gt 0
            echo "Configuration for $PROJECT_NAME has changed since this container was created:"
            printf '%s\n' $drift_lines
            read -P "Restart the container to apply these changes? [Y/n] " answer
            or set answer n
            if test -z "$answer"; or string match -qi 'y*' -- $answer
                echo "Restarting sandbox for $PROJECT_NAME..."
                _sandbox_recreate $container_name $PROJECT_PATH $PROJECT_NAME
                or begin
                    echo "Error: Failed to recreate container."
                    return 1
                end
                _sandbox_attach $container_name $PROJECT_NAME
                return
            end
        end
    end
```

Behavior: empty answer (Enter) or `y…` → recreate + attach + return; `n…` → fall through to the normal `switch` and attach as-is. On EOF (non-interactive) `read` fails, `answer` is set to `n`, so we never auto-destroy. Drift is detected for any existing state (running, exited, created, paused), since the check runs before `start`/attach.

- [ ] **Step 2: Reload**

```bash
source ~/.config/fish/functions/claude-sandbox.fish
```

- [ ] **Step 3: Verify the "no drift" path is silent**

From a project whose container already exists and whose config is unchanged:

```bash
claude-sandbox
```

Expected: no drift message; same attach output as before.

- [ ] **Step 4: Verify the drift prompt appears and default-Yes restarts**

In a project with an existing container, add a mount, then reopen:

```bash
claude-sandbox mounts add '~/cs-extra:/extra'
claude-sandbox
```

Expected:

```
Configuration for <project> has changed since this container was created:
  + volume ~/cs-extra:/extra
Restart the container to apply these changes? [Y/n]
```

Press Enter → `Restarting sandbox for <project>...`, the container is recreated, VS Code opens.

- [ ] **Step 5: Verify drift is gone after the restart**

```bash
claude-sandbox
```

Expected: no drift prompt (the recreated container now carries an up-to-date snapshot). Then revert the test mount:

```bash
claude-sandbox mounts remove '~/cs-extra:/extra'
```

(Re-running `claude-sandbox` will now prompt again to apply the removal — answer `n` to leave the container, or `y` to recreate.)

- [ ] **Step 6: Verify answering `n` attaches without recreating**

With drift present (e.g. right after a `mounts add`), run `claude-sandbox` and type `n`. Expected: it skips recreation and prints the normal `Attaching to running sandbox...`, leaving the container untouched. Clean up any test mount afterward with `claude-sandbox mounts remove ...`.

- [ ] **Step 7: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: detect config drift on reopen and prompt to restart"
```

---

### Task 6: Add the `restart` subcommand

Wire `restart <target>` into `function claude-sandbox`: resolve like `open`, recreate + attach, prompt before creating when no container exists.

**Files:**
- Modify: `functions/claude-sandbox.fish` (the `open` subcommand block ends at line 702; top-level `--help` block around lines 451-466)

- [ ] **Step 1: Add the `restart` line to the top-level `--help` output**

In the `# --- top-level --help ---` block, find the `open <target>` help line (added by the open feature):

```fish
        printf "  %-34s%s\n" "open <target>"         "Open VS Code for a sandbox by path or container name"
```

Insert directly after it:

```fish
        printf "  %-34s%s\n" "restart <target>"      "Recreate a sandbox with current config and reattach"
```

- [ ] **Step 2: Add the `restart` subcommand block**

Insert this block immediately **after** the `# --- open subcommand ---` block (after its closing `end` at line 702) and **before** the `# --- launch flow ---` comment:

```fish
    # --- restart subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = restart
        if contains -- --help $argv
            echo "Usage: claude-sandbox restart <target>"
            echo ""
            echo "  Recreates a sandbox container with the current configuration and"
            echo "  reattaches VS Code. Use this to apply configuration changes"
            echo "  (e.g. 'claude-sandbox mounts add') to an existing container."
            echo ""
            echo "  <target> may be either:"
            echo "    - A project path (absolute or relative)."
            echo "    - A container name (e.g. claude-sandbox-abc12345) from"
            echo "      'claude-sandbox list'."
            echo ""
            echo "  Any existing container for the target is stopped and removed first;"
            echo "  this ends any running Claude session in that container. If no"
            echo "  container exists for a path target, you are prompted before one"
            echo "  is created."
            return 0
        end
        if test (count $argv) -lt 2
            echo "Usage: claude-sandbox restart <target>"
            return 1
        end
        set -l target $argv[2]

        # Resolve target like 'open': labeled container name first, then path.
        set -l resolved
        set -l labeled_path (docker inspect --format '{{ index .Config.Labels "claude-sandbox.project" }}' $target 2>/dev/null)
        if test -n "$labeled_path"
            set resolved $labeled_path
        else
            set resolved (realpath $target 2>/dev/null)
            if test -z "$resolved"
                echo "Error: '$target' is neither an existing sandbox container nor a valid path."
                return 1
            end
        end

        set -l project_name (basename $resolved)
        set -l container_name (_sandbox_container_name $resolved)

        _sandbox_preflight $resolved; or return 1

        set -l rs_status (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)
        if test -n "$rs_status"
            # Existing container: show what will change (for transparency), then recreate.
            set -l drift_lines (_sandbox_config_diff $resolved $container_name)
            if test (count $drift_lines) -gt 0
                echo "Applying configuration changes to $project_name:"
                printf '%s\n' $drift_lines
            end
            echo "Restarting sandbox for $project_name..."
        else
            # No container yet: confirm before creating (default No).
            read -P "No sandbox exists for $resolved. Create one? [y/N] " answer
            or set answer n
            if not string match -qi 'y*' -- $answer
                echo "Aborted."
                return 1
            end
            echo "Creating new sandbox for $project_name..."
        end

        _sandbox_recreate $container_name $resolved $project_name
        or begin
            echo "Error: Failed to recreate container."
            return 1
        end
        _sandbox_attach $container_name $project_name
        return
    end
```

- [ ] **Step 3: Reload and verify help text**

```bash
source ~/.config/fish/functions/claude-sandbox.fish
claude-sandbox --help
```

Expected: `restart <target>` appears under Subcommands.

```bash
claude-sandbox restart --help
```

Expected: prints the usage block from Step 2.

- [ ] **Step 4: Verify missing argument errors**

```bash
claude-sandbox restart
```

Expected: `Usage: claude-sandbox restart <target>` and exit status 1.

- [ ] **Step 5: Verify restart of an existing container by name**

Pick an existing container from `claude-sandbox list`:

```bash
claude-sandbox restart <container-name-from-list>
```

Expected: `Restarting sandbox for <project>...` (with an `Applying configuration changes:` diff block if its config drifted), the container is recreated, and VS Code opens.

- [ ] **Step 6: Verify restart by path applies a config change**

In a project with an existing container:

```bash
claude-sandbox mounts add '~/cs-restart:/r'
claude-sandbox restart .
```

Expected: an `Applying configuration changes to <project>:` block listing `+ volume ~/cs-restart:/r`, then recreation + attach. Confirm it took:

```bash
docker inspect --format '{{json .Mounts}}' (_sandbox_container_name (realpath .)) | grep -q cs-restart && echo "MOUNT APPLIED"
```

Expected: `MOUNT APPLIED`. Then revert: `claude-sandbox mounts remove '~/cs-restart:/r'` and `claude-sandbox restart .`.

- [ ] **Step 7: Verify the create prompt for a path with no container (default No aborts)**

```bash
mkdir -p /tmp/cs-restart-new && cd /
printf 'n\n' | claude-sandbox restart /tmp/cs-restart-new
```

Expected:

```
No sandbox exists for /tmp/cs-restart-new. Create one? [y/N]
Aborted.
```

Exit status 1, and no container created (`docker ps -a | grep cs-restart-new` shows nothing). Now confirm Yes creates it:

```bash
printf 'y\n' | claude-sandbox restart /tmp/cs-restart-new   # answer the git-auth wizard if it appears
```

Expected: `Creating new sandbox for cs-restart-new...`, container created, VS Code opens. Tear down:

```bash
cd /tmp/cs-restart-new && claude-sandbox stop --rm; cd / && rm -rf /tmp/cs-restart-new
```

- [ ] **Step 8: Verify a non-existent path errors (no create offer)**

```bash
claude-sandbox restart /no/such/path
```

Expected:

```
Error: '/no/such/path' is neither an existing sandbox container nor a valid path.
```

Exit status 1 (the create prompt is **not** offered for paths that don't resolve on disk).

- [ ] **Step 9: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: add claude-sandbox restart subcommand"
```

---

### Task 7: Add tab completion for `restart`

Register `restart` in the completion list and reuse the `open` target source.

**Files:**
- Modify: `completions/claude-sandbox.fish`

- [ ] **Step 1: Add `restart` to the `$subcommands` list**

Change line 3 from:

```fish
set -l subcommands stop list open git-auth mounts global
```

to:

```fish
set -l subcommands stop list open restart git-auth mounts global
```

- [ ] **Step 2: Add the top-level completion entry for `restart`**

After the existing `-a open` block (the one with description `'Open VS Code for a sandbox by path or container name'`, around lines 18-20), insert:

```fish
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a restart -d 'Recreate a sandbox with current config and reattach'
```

- [ ] **Step 3: Add the target-completion rules for `restart`**

The `__claude_sandbox_open_targets` helper already exists (added by the `open` feature, around line 45). After the existing `open` completion rules (the `-a '(__claude_sandbox_open_targets)'` block and its `--help` rule, around lines 58-64), insert:

```fish
complete -c claude-sandbox -f \
    -n "__fish_seen_subcommand_from restart" \
    -a '(__claude_sandbox_open_targets)'

complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from restart" \
    -l help -d 'Show usage'
```

- [ ] **Step 4: Reload completions and verify**

```bash
source ~/.config/fish/completions/claude-sandbox.fish
```

In an interactive fish session:

```
claude-sandbox <TAB>
```

Expected: `restart` appears with description "Recreate a sandbox with current config and reattach".

```
claude-sandbox restart <TAB>
```

Expected: one entry per existing container's project path (described by docker status) plus one per container hash name — identical candidate set to `claude-sandbox open <TAB>`. No filesystem completion.

- [ ] **Step 5: Commit**

```bash
git add completions/claude-sandbox.fish
git commit -m "feat: tab completion for claude-sandbox restart"
```

---

### Task 8: README update

Document `restart` and drift detection in the quick reference and "How it works" sections.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a quick-reference sentence**

Find the line added by the `open` feature in the `## Quick reference` section:

```
Use `claude-sandbox open <path-or-container>` from anywhere to attach VS Code to a sandbox. Tab completion lists every existing container's path and hash.
```

Insert after it:

```
Use `claude-sandbox restart <path-or-container>` to recreate a container with the current config (the way to apply changes from `claude-sandbox mounts add` and friends). On reopen, claude-sandbox detects when a container's config has drifted from `configurations.yml`, shows what changed, and offers to restart.
```

- [ ] **Step 2: Add a "How it works" bullet**

In the `## How it works` list, add a bullet (after the "Per-project containers" bullet):

```
- **Config drift**: each container records a snapshot of the config it was built from (a `claude-sandbox.config-snapshot` label). Reopening a project compares that snapshot to the current `configurations.yml`; if they differ it lists the changes and offers to restart. `claude-sandbox restart` applies changes on demand.
```

- [ ] **Step 3: Verify the doc reads well**

Read the README top to bottom and confirm the additions match the project's terse style.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document restart subcommand and config-drift detection"
```

---

### Task 9: End-to-end smoke test

Exercise the whole feature from a fresh shell.

- [ ] **Step 1: Open a fresh terminal so all functions/completions reload**

```bash
exec fish
```

- [ ] **Step 2: Confirm a freshly created container carries a snapshot label**

```bash
mkdir -p /tmp/cs-e2e && cd /tmp/cs-e2e
claude-sandbox   # answer git-auth wizard (Skip is fine)
docker inspect --format '{{ index .Config.Labels "claude-sandbox.config-snapshot" }}' (_sandbox_container_name (pwd)) | base64 -d
```

Expected: decoded snapshot lines (at least `image` and `git_auth_type`).

- [ ] **Step 3: Reopen with no changes — no drift prompt**

```bash
claude-sandbox
```

Expected: normal attach, no drift message.

- [ ] **Step 4: Add a mount, reopen, accept restart**

```bash
claude-sandbox mounts add '~/cs-e2e-data:/data'
claude-sandbox   # press Enter at the [Y/n] prompt
```

Expected: drift block showing `+ volume ~/cs-e2e-data:/data`, then restart + attach.

- [ ] **Step 5: Confirm the mount is now live and drift is cleared**

```bash
docker inspect --format '{{json .Mounts}}' (_sandbox_container_name (pwd)) | grep -q cs-e2e-data && echo "MOUNT LIVE"
claude-sandbox   # should be silent now
```

Expected: `MOUNT LIVE`, and the second `claude-sandbox` shows no drift prompt.

- [ ] **Step 6: `restart` by path applies a removal**

```bash
claude-sandbox mounts remove '~/cs-e2e-data:/data'
claude-sandbox restart .
docker inspect --format '{{json .Mounts}}' (_sandbox_container_name (pwd)) | grep -q cs-e2e-data || echo "MOUNT GONE"
```

Expected: an `Applying configuration changes:` block with `- volume ~/cs-e2e-data:/data`, then `MOUNT GONE`.

- [ ] **Step 7: `restart` create prompt for a new path**

```bash
cd / && printf 'n\n' | claude-sandbox restart /tmp/cs-e2e-brand-new 2>&1 | head -3
```

Expected: prompt `No sandbox exists for /tmp/cs-e2e-brand-new. Create one? [y/N]` followed by `Aborted.` (path resolves only if it exists — if it doesn't, you'll instead get the "neither ... nor a valid path" error, which is also correct).

- [ ] **Step 8: Tab completion parity check**

In interactive fish:

```
claude-sandbox restart <TAB>
```

Expected: same candidates as `claude-sandbox open <TAB>`.

- [ ] **Step 9: Tear down**

```bash
cd /tmp/cs-e2e && claude-sandbox stop --rm
cd / && rm -rf /tmp/cs-e2e
```

- [ ] **Step 10: All clear — no commit needed**

If everything passes, the feature is complete. If anything failed, fix the relevant earlier task and re-run.
