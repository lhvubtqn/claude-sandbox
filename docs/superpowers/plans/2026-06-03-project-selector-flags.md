# Project-selector flags (`-p/--project` and `-g`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a universal `-p/--project <id|path>` selector and replace the `global` subcommand with a `-g/--global` flag in the `claude-sandbox` fish CLI.

**Architecture:** A front-door parsing block at the top of the `claude-sandbox` function consumes leading `-p`/`-g` flags, resolves a single `target_path` (or sets global mode), strips the flags from `argv`, and lets the existing subcommand dispatch chain run with each project-scoped subcommand reading `target_path` instead of `pwd`. A new `_sandbox_resolve_target` helper centralizes the path/hash/name resolution currently duplicated in `open` and `restart`.

**Tech Stack:** fish shell (functions + completions), `yq` for YAML config, `docker` for container introspection. No automated test framework exists in this repo; verification is concrete `fish -c` commands and round-trip config checks run on a host with fish/yq/docker installed (the tool's normal environment).

---

## File Structure

- `functions/claude-sandbox.fish` — all CLI logic. Modified: add `_sandbox_resolve_target`, add the front-door parser inside `claude-sandbox`, rewire project-scoped subcommands, delete the `global` block, update help text.
- `completions/claude-sandbox.fish` — tab completions. Modified: add `-p`/`-g` flags, remove `global` keyword rules.
- `README.md` — user docs. Modified: `global mounts` → `-g mounts`; document `-p`.

No new files. All changes follow the existing hand-rolled `if`/`switch` style; no conversion to `argparse`.

---

## Task 1: Extract `_sandbox_resolve_target` and refactor `open`/`restart`

Pure refactor — no behavior change. Centralizes the duplicated container-ref-then-realpath resolution so the parser (Task 2) can reuse it.

**Files:**
- Modify: `functions/claude-sandbox.fish` (add helper near other `_sandbox_*` helpers; edit `open` ~813-855 and `restart` ~857-935)

- [ ] **Step 1: Add the `_sandbox_resolve_target` helper**

Insert this function immediately before `function _sandbox_container_name` (currently around line 174):

```fish
function _sandbox_resolve_target
    # Usage: _sandbox_resolve_target <value>
    # Resolves a project path from a value that may be a container hash, a full
    # container name, or a filesystem path. Container refs resolve via the
    # claude-sandbox.project label (the container must exist); a path falls back
    # to realpath and is valid even when no container exists yet.
    # Echoes the absolute path and returns 0, or echoes nothing and returns 1.
    set -l value $argv[1]
    for ref in $value claude-sandbox-$value
        set -l labeled_path (docker inspect --format '{{ index .Config.Labels "claude-sandbox.project" }}' $ref 2>/dev/null)
        if test -n "$labeled_path"
            echo $labeled_path
            return 0
        end
    end
    set -l resolved (realpath $value 2>/dev/null)
    if test -n "$resolved"
        echo $resolved
        return 0
    end
    return 1
end
```

- [ ] **Step 2: Refactor the `open` subcommand to use the helper**

In the `open` block, replace the resolution tail. Find:

```fish
        set -l target $argv[2]

        # Try as a container reference first: either the full name
        # (claude-sandbox-abc12345) or the bare hash (abc12345) that tab
        # completion inserts. Must exist AND carry our label.
        for ref in $target claude-sandbox-$target
            set -l labeled_path (docker inspect --format '{{ index .Config.Labels "claude-sandbox.project" }}' $ref 2>/dev/null)
            if test -n "$labeled_path"
                _sandbox_launch $labeled_path
                return
            end
        end

        # Fall back to path mode.
        set -l resolved (realpath $target 2>/dev/null)
        if test -z "$resolved"
            echo "Error: '$target' is neither an existing sandbox container nor a valid path."
            return 1
        end
        _sandbox_launch $resolved
        return
```

Replace with:

```fish
        set -l target $argv[2]
        set -l resolved (_sandbox_resolve_target $target)
        if test -z "$resolved"
            echo "Error: '$target' is neither an existing sandbox container nor a valid path."
            return 1
        end
        _sandbox_launch $resolved
        return
```

- [ ] **Step 3: Refactor the `restart` subcommand to use the helper**

In the `restart` block, find:

```fish
        set -l target $argv[2]

        # Resolve target like 'open': container reference first (full name or bare
        # hash that tab completion inserts), then fall back to a project path.
        set -l resolved
        for ref in $target claude-sandbox-$target
            set -l labeled_path (docker inspect --format '{{ index .Config.Labels "claude-sandbox.project" }}' $ref 2>/dev/null)
            if test -n "$labeled_path"
                set resolved $labeled_path
                break
            end
        end
        if test -z "$resolved"
            set resolved (realpath $target 2>/dev/null)
            if test -z "$resolved"
                echo "Error: '$target' is neither an existing sandbox container nor a valid path."
                return 1
            end
        end
```

Replace with:

```fish
        set -l target $argv[2]

        # Resolve target like 'open': container reference first (full name or bare
        # hash that tab completion inserts), then fall back to a project path.
        set -l resolved (_sandbox_resolve_target $target)
        if test -z "$resolved"
            echo "Error: '$target' is neither an existing sandbox container nor a valid path."
            return 1
        end
```

- [ ] **Step 4: Verify the helper resolves a path and rejects garbage**

Run (on a host with fish):

```bash
fish -c 'source functions/claude-sandbox.fish
echo "path:"; _sandbox_resolve_target /tmp; echo "rc=$status"
echo "garbage:"; _sandbox_resolve_target /no/such/path/xyz123; echo "rc=$status"'
```

Expected:
```
path:
/tmp
rc=0
garbage:
rc=1
```

- [ ] **Step 5: Verify `open`/`restart` still reject an invalid target (no regression)**

```bash
fish -c 'source functions/claude-sandbox.fish; claude-sandbox open /no/such/xyz123'
```

Expected: `Error: '/no/such/xyz123' is neither an existing sandbox container nor a valid path.` and non-zero exit.

- [ ] **Step 6: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "refactor: extract _sandbox_resolve_target from open/restart"
```

---

## Task 2: Front-door flag parser, `-g mounts` routing, delete `global` block

Adds leading-flag parsing and wires the `mounts` subcommand (both project and global). After this task, `mounts`/`-p X mounts`/`-g mounts` all work and the old `global` keyword is gone. `git-auth`/`stop`/`open`/`restart` still default to `pwd` (wired in Tasks 3–4).

**Files:**
- Modify: `functions/claude-sandbox.fish` (`claude-sandbox` function: add parser after line ~595; delete `global` block ~616-664; edit `mounts` block ~764-811; edit launch flow ~937-938)

- [ ] **Step 1: Add the parser block**

In `function claude-sandbox`, immediately after these two lines (currently 594-595):

```fish
    set -l PROJECT_PATH (pwd)
    set -l PROJECT_NAME (basename $PROJECT_PATH)
```

Insert:

```fish
    # --- leading project/global selector flags (must precede the subcommand) ---
    set -l target_path $PROJECT_PATH
    set -l global_mode 0
    set -l project_flag 0
    set -l _subcmds stop list open restart git-auth mounts
    while test (count $argv) -gt 0
        switch $argv[1]
            case -p --project
                if test (count $argv) -lt 2; or contains -- $argv[2] $_subcmds
                    echo "Error: -p requires a project path or container reference."
                    return 1
                end
                set project_flag 1
                set -l resolved (_sandbox_resolve_target $argv[2])
                if test -z "$resolved"
                    echo "Error: '$argv[2]' is neither an existing sandbox container nor a valid path."
                    return 1
                end
                set target_path $resolved
                set -e argv[2]
                set -e argv[1]
            case -g --global
                set global_mode 1
                set -e argv[1]
            case '*'
                break
        end
    end
    set -l target_name (basename $target_path)

    # Flag-combination validation
    if test $global_mode -eq 1; and test $project_flag -eq 1
        echo "Error: -g and -p are mutually exclusive."
        return 1
    end
    if test $global_mode -eq 1
        if test (count $argv) -eq 0; or test "$argv[1]" != mounts
            echo "Error: -g is only valid with 'mounts'."
            return 1
        end
    end
    if test $project_flag -eq 1; and test (count $argv) -gt 0; and test "$argv[1]" = list
        echo "Error: list is cross-project; -p/-g not applicable."
        return 1
    end
```

- [ ] **Step 2: Delete the `global` subcommand block**

Remove the entire block starting at the `# --- global subcommand ---` comment through its closing `end` and trailing blank line (currently lines 616-665):

```fish
    # --- global subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = global
        ...
        return
    end
```

(Delete all of it; `-g` now drives global mounts via Step 3.)

- [ ] **Step 3: Rewire the `mounts` block to honor global mode and `target_path`**

Replace the `switch $action` body inside the `mounts` block so each action branches on `global_mode`. Find the current block (starting `# --- mounts subcommand ---`, the `switch $action` through its closing `end`) and replace the `switch $action ... end` with:

```fish
        switch $action
            case add
                if test (count $argv) -lt 3
                    echo "Usage: claude-sandbox [-p <project>|-g] mounts add <source>:<target>[:<options>]"
                    return 1
                end
                if test $global_mode -eq 1
                    _sandbox_global_mounts_add $argv[3]
                    echo "Added global mount: $argv[3]"
                else
                    _sandbox_mounts_add $target_path $argv[3]
                    echo "Added mount for $target_path: $argv[3]"
                end
            case remove
                if test (count $argv) -lt 3
                    echo "Usage: claude-sandbox [-p <project>|-g] mounts remove <source>:<target>[:<options>]"
                    return 1
                end
                if test $global_mode -eq 1
                    _sandbox_global_mounts_remove $argv[3]
                    echo "Removed global mount: $argv[3]"
                else
                    _sandbox_mounts_remove $target_path $argv[3]
                    echo "Removed mount for $target_path: $argv[3]"
                end
            case list
                if test $global_mode -eq 1
                    set -l mounts (_sandbox_global_mounts_list)
                    if test (count $mounts) -eq 0
                        echo "No global mounts configured"
                    else
                        for m in $mounts
                            echo $m
                        end
                    end
                else
                    set -l mounts (_sandbox_mounts_list $target_path)
                    if test (count $mounts) -eq 0
                        echo "No extra mounts configured for $target_path"
                    else
                        for m in $mounts
                            echo $m
                        end
                    end
                end
            case clear
                if test $global_mode -eq 1
                    _sandbox_global_mounts_clear
                    echo "Cleared all global mounts"
                else
                    _sandbox_mounts_clear $target_path
                    echo "Cleared all mounts for $target_path"
                end
            case '*'
                echo "Usage: claude-sandbox [-p <project>|-g] mounts {add <spec>|remove <spec>|list|clear}"
                return 1
        end
```

- [ ] **Step 4: Point the launch flow at `target_path`**

At the bottom of the function, find:

```fish
    # --- launch flow ---
    _sandbox_launch $PROJECT_PATH
```

Replace the last line with:

```fish
    # --- launch flow ---
    _sandbox_launch $target_path
```

(This makes bare `claude-sandbox -p X` launch project X, while plain `claude-sandbox` still uses `pwd` since `target_path` defaults to it.)

- [ ] **Step 5: Verify global mounts round-trip via `-g`**

```bash
fish -c 'source functions/claude-sandbox.fish
claude-sandbox -g mounts add wf-test-vol:/tmp/wf-test
claude-sandbox -g mounts list | grep wf-test-vol
claude-sandbox -g mounts remove wf-test-vol:/tmp/wf-test
claude-sandbox -g mounts list | grep -c wf-test-vol'
```

Expected: the `add` line prints `Added global mount: wf-test-vol:/tmp/wf-test`, the first `grep` prints the entry, and the final `grep -c` prints `0` (removed). Leaves config clean.

- [ ] **Step 6: Verify flag-combination errors**

```bash
fish -c 'source functions/claude-sandbox.fish; claude-sandbox -g -p /tmp mounts list'; echo "rc=$status"
fish -c 'source functions/claude-sandbox.fish; claude-sandbox -g list'; echo "rc=$status"
fish -c 'source functions/claude-sandbox.fish; claude-sandbox -p list mounts list'; echo "rc=$status"
fish -c 'source functions/claude-sandbox.fish; claude-sandbox -p /tmp list'; echo "rc=$status"
fish -c 'source functions/claude-sandbox.fish; claude-sandbox global mounts list'; echo "rc=$status"
```

Expected, respectively:
- `Error: -g and -p are mutually exclusive.` `rc=1`
- `Error: -g is only valid with 'mounts'.` `rc=1`
- `Error: -p requires a project path or container reference.` `rc=1` (value `list` is a known subcommand)
- `Error: list is cross-project; -p/-g not applicable.` `rc=1`
- `Error: Docker is not running. Please start Docker Desktop first.` `rc=1`

> Note on the last case: with `global` removed, `global` is no longer a subcommand. The parser breaks on it (not a flag), no subcommand `if` block matches it, and the function falls through to the launch flow — `_sandbox_launch $target_path` against `pwd`, whose first step is the `docker info` preflight. Without docker that prints the "Docker is not running" error. The point of this check is simply that `global` no longer triggers any global-mounts behavior (no mount output, no "No global mounts configured").

- [ ] **Step 7: Verify project-scoped mounts via `-p <path>` (pre-container)**

```bash
fish -c 'source functions/claude-sandbox.fish
claude-sandbox -p /tmp/wf-fake-proj mounts add foo:/bar
claude-sandbox -p /tmp/wf-fake-proj mounts list
claude-sandbox -p /tmp/wf-fake-proj mounts clear'
```

Expected: realpath of `/tmp/wf-fake-proj` does not exist, so `_sandbox_resolve_target` returns empty → `Error: '/tmp/wf-fake-proj' is neither an existing sandbox container nor a valid path.` To test a real pre-container path, use an existing dir:

```bash
mkdir -p /tmp/wf-real-proj
fish -c 'source functions/claude-sandbox.fish
claude-sandbox -p /tmp/wf-real-proj mounts add foo:/bar
claude-sandbox -p /tmp/wf-real-proj mounts list | grep foo:/bar
claude-sandbox -p /tmp/wf-real-proj mounts clear'
rmdir /tmp/wf-real-proj
```

Expected: `Added mount for /tmp/wf-real-proj: foo:/bar`, the `grep` prints `foo:/bar`, then `Cleared all mounts for /tmp/wf-real-proj`. Config left clean.

- [ ] **Step 8: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: add -p/-g flag parser, route -g mounts, drop global subcommand"
```

---

## Task 3: Wire `-p` into `git-auth` and `stop`

**Files:**
- Modify: `functions/claude-sandbox.fish` (`git-auth` block ~712-762; `stop` block ~666-696)

- [ ] **Step 1: Use `target_path`/`target_name` in `git-auth`**

In the `git-auth` block, replace every `$PROJECT_PATH` with `$target_path` and every `$PROJECT_NAME` with `$target_name`. Specifically:

- `case set`: `_sandbox_git_auth_wizard $PROJECT_PATH $PROJECT_NAME` → `_sandbox_git_auth_wizard $target_path $target_name`
- `case show`: the three `_sandbox_config_read_git_auth_*` calls and the `"No git auth configured for $PROJECT_PATH"` message → use `$target_path`
- `case clear`: `_sandbox_config_delete $PROJECT_PATH` and its echo → use `$target_path`
- `case list`: unchanged (it iterates all projects; no path needed)

- [ ] **Step 2: Use `target_path` in `stop`**

In the `stop` block, replace `$PROJECT_PATH` with `$target_path`:

- `set -l container_name (_sandbox_container_name $PROJECT_PATH)` → `(_sandbox_container_name $target_path)`
- `echo "No container found for $PROJECT_PATH"` → `$target_path`

- [ ] **Step 3: Verify `-p` selects a different project for `git-auth show`**

```bash
mkdir -p /tmp/wf-ga-proj
fish -c 'source functions/claude-sandbox.fish; claude-sandbox -p /tmp/wf-ga-proj git-auth show'
rmdir /tmp/wf-ga-proj
```

Expected: `No git auth configured for /tmp/wf-ga-proj` (proves the path came from `-p`, not `pwd`).

- [ ] **Step 4: Verify `-p` selects a different project for `stop`**

```bash
mkdir -p /tmp/wf-stop-proj
fish -c 'source functions/claude-sandbox.fish; claude-sandbox -p /tmp/wf-stop-proj stop'
rmdir /tmp/wf-stop-proj
```

Expected: `No container found for /tmp/wf-stop-proj` and non-zero exit (no docker container for that path).

- [ ] **Step 5: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: honor -p/--project in git-auth and stop"
```

---

## Task 4: Wire `-p` into `open` and `restart`

When `-p` is supplied, `open`/`restart` use `target_path` directly; otherwise the positional argument still works (backward compatible).

**Files:**
- Modify: `functions/claude-sandbox.fish` (`open` block ~813-855; `restart` block ~857-935)

- [ ] **Step 1: Short-circuit `open` when `-p` was given**

In the `open` block, immediately after the `--help` handling and before `if test (count $argv) -lt 2`, insert:

```fish
        if test $project_flag -eq 1
            _sandbox_launch $target_path
            return
        end
```

- [ ] **Step 2: Short-circuit `restart` when `-p` was given**

In the `restart` block, after the `--help` handling, replace:

```fish
        if test (count $argv) -lt 2
            echo "Usage: claude-sandbox restart <target>"
            return 1
        end
        set -l target $argv[2]

        # Resolve target like 'open': container reference first (full name or bare
        # hash that tab completion inserts), then fall back to a project path.
        set -l resolved (_sandbox_resolve_target $target)
        if test -z "$resolved"
            echo "Error: '$target' is neither an existing sandbox container nor a valid path."
            return 1
        end
```

with:

```fish
        set -l resolved
        if test $project_flag -eq 1
            set resolved $target_path
        else
            if test (count $argv) -lt 2
                echo "Usage: claude-sandbox restart <target>"
                return 1
            end
            set resolved (_sandbox_resolve_target $argv[2])
            if test -z "$resolved"
                echo "Error: '$argv[2]' is neither an existing sandbox container nor a valid path."
                return 1
            end
        end
```

(The rest of the `restart` block already uses `$resolved` for `project_name`/`container_name` — no further change.)

- [ ] **Step 3: Verify `-p X open` routes through `target_path`**

Without docker the launch will fail at `docker info`, but we can confirm the `-p` short-circuit is taken (it should NOT print the `open` usage error). Run:

```bash
mkdir -p /tmp/wf-open-proj
fish -c 'source functions/claude-sandbox.fish; claude-sandbox -p /tmp/wf-open-proj open' 2>&1 | head -1
rmdir /tmp/wf-open-proj
```

Expected first line: `Error: Docker is not running. Please start Docker Desktop first.` (preflight from `_sandbox_launch`) — proving it reached launch, not a usage error. On a host with docker running it attaches/creates the container for `/tmp/wf-open-proj`.

- [ ] **Step 4: Verify positional `open`/`restart` still work (no regression)**

```bash
fish -c 'source functions/claude-sandbox.fish; claude-sandbox restart /no/such/xyz123'; echo "rc=$status"
```

Expected: `Error: '/no/such/xyz123' is neither an existing sandbox container nor a valid path.` `rc=1`.

- [ ] **Step 5: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "feat: honor -p/--project in open and restart"
```

---

## Task 5: Update help text

**Files:**
- Modify: `functions/claude-sandbox.fish` (top-level `--help` ~597-614; `mounts --help` ~767-777)

- [ ] **Step 1: Update the top-level `--help`**

In the top-level `--help` block, replace the two subcommand lines:

```fish
        printf "  %-34s%s\n" "mounts <action>"       "Manage per-project volume entries"
        printf "  %-34s%s\n" "global mounts <action>" "Manage always-on global volume entries"
```

with:

```fish
        printf "  %-34s%s\n" "mounts <action>"       "Manage current project's volume entries"
        printf "  %-34s%s\n" "-g mounts <action>"    "Manage always-on global volume entries"
```

And add, just before the closing `echo ""` / `Run 'claude-sandbox <subcommand> --help'` lines, a global-flags note:

```fish
        echo ""
        echo "Global flags (before the subcommand):"
        printf "  %-34s%s\n" "-p, --project <id|path>" "Target another project (path, container hash, or name)"
        printf "  %-34s%s\n" ""                        "Applies to: mounts, git-auth, open, restart, stop"
        printf "  %-34s%s\n" "-g, --global"            "Operate on global config (mounts only)"
```

- [ ] **Step 2: Update the `mounts --help`**

Replace the `mounts` `--help` body:

```fish
            echo "Usage: claude-sandbox mounts {add <spec>|remove <spec>|list|clear}"
            echo ""
            printf "  %-24s%s\n" "add <spec>"    "Add a volume entry for current project"
            printf "  %-24s%s\n" "remove <spec>" "Remove a volume entry"
            printf "  %-24s%s\n" "list"          "Show all volume entries for current project"
            printf "  %-24s%s\n" "clear"         "Remove all volume entries for current project"
            echo ""
            echo "  <spec> format: <host-path>:<container-path>[:<options>]"
            echo "  Supports \${WORKDIR}, \${HOME}, and ~ in host paths."
            return 0
```

with:

```fish
            echo "Usage: claude-sandbox [-p <project>|-g] mounts {add <spec>|remove <spec>|list|clear}"
            echo ""
            printf "  %-24s%s\n" "add <spec>"    "Add a volume entry"
            printf "  %-24s%s\n" "remove <spec>" "Remove a volume entry"
            printf "  %-24s%s\n" "list"          "Show all volume entries"
            printf "  %-24s%s\n" "clear"         "Remove all volume entries"
            echo ""
            echo "  Target: current project (default), another project (-p <id|path>),"
            echo "          or always-on global volumes (-g)."
            echo "  <spec> format: <host-path>:<container-path>[:<options>]"
            echo "  Supports \${WORKDIR}, \${HOME}, and ~ in host paths."
            return 0
```

- [ ] **Step 3: Verify help text**

```bash
fish -c 'source functions/claude-sandbox.fish; claude-sandbox --help' | grep -E '\-g mounts|--project'
fish -c 'source functions/claude-sandbox.fish; claude-sandbox mounts --help' | grep -E '\-p <project>'
```

Expected: the first prints the `-g mounts <action>` and `-p, --project <id|path>` lines; the second prints the `Usage: claude-sandbox [-p <project>|-g] mounts ...` line. Confirm no remaining line contains `global mounts`:

```bash
fish -c 'source functions/claude-sandbox.fish; claude-sandbox --help' | grep -c 'global mounts'
```

Expected: `0`.

- [ ] **Step 4: Commit**

```bash
git add functions/claude-sandbox.fish
git commit -m "docs: update help text for -p/--project and -g flags"
```

---

## Task 6: Rework completions

**Files:**
- Modify: `completions/claude-sandbox.fish`

- [ ] **Step 1: Drop `global` from the subcommand list**

Change:

```fish
set -l subcommands stop list open restart git-auth mounts global
```

to:

```fish
set -l subcommands stop list open restart git-auth mounts
```

- [ ] **Step 2: Remove the `global` top-level completion**

Delete this block:

```fish
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a global -d 'Manage global configuration'
```

- [ ] **Step 3: Add `-p`/`-g` leading-flag completions**

Immediately after the top-level subcommand completions (after the `mounts` `-a` completion block, before the `# stop` section), add:

```fish
# Leading selector flags (offered before a subcommand is chosen).
# -p takes a required argument: an existing container (hash/path) or any directory.
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -s p -l project -r -d 'Target another project (id or path)' \
    -a '(__claude_sandbox_open_targets)'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -s p -l project -r -a '(__fish_complete_directories)'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -s g -l global -d 'Operate on global config (mounts only)'
```

(`__claude_sandbox_open_targets` is defined later in this file; fish resolves it at completion time, so order is fine.)

- [ ] **Step 4: Restrict subcommands after `-g` to `mounts`**

The existing top-level subcommand completions fire on `not __fish_seen_subcommand_from $subcommands`. After `-g`, all of them would still be offered. Constrain them by appending `; and not __fish_seen_argument -s g -l global` to each top-level subcommand completion's `-n` condition EXCEPT the `mounts` one. For example, the `stop` completion becomes:

```fish
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands; and not __fish_seen_argument -s g -l global" \
    -a stop   -d 'Stop this project'\''s container'
```

Apply the same `; and not __fish_seen_argument -s g -l global` suffix to the `list`, `open`, `restart`, and `git-auth` top-level `-a` completions. Leave the `mounts` top-level completion unchanged so `-g <TAB>` still offers `mounts`.

- [ ] **Step 5: Remove the old `global → mounts → actions` completion block**

Delete the entire trailing block under the `# global → mounts → actions` comment (the six `complete` rules conditioned on `__fish_seen_subcommand_from global`).

- [ ] **Step 6: Simplify the `mounts` action conditions**

The `mounts` action completions currently guard with `and not __fish_seen_subcommand_from global`. With `global` gone, remove that clause from each of the four action rules and the `--help` rule. For example:

```fish
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a add    -d 'Add a volume entry'
```

(Repeat the removal of `; and not __fish_seen_subcommand_from global` for `remove`, `list`, `clear`, and the `mounts` `--help` rule.)

- [ ] **Step 7: Verify completions load without error**

```bash
fish -c 'source completions/claude-sandbox.fish; echo OK'
```

Expected: `OK` with no error output. Confirm `global` is gone:

```bash
grep -c 'global' completions/claude-sandbox.fish
```

Expected: `0`.

- [ ] **Step 8: Commit**

```bash
git add completions/claude-sandbox.fish
git commit -m "feat: completions for -p/-g flags; remove global keyword"
```

---

## Task 7: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Quick reference section**

In `README.md`, the Quick reference shows `claude-sandbox global --help`. Replace that line:

```
claude-sandbox global --help
```

with:

```
claude-sandbox -g mounts --help
claude-sandbox -p <id|path> mounts --help
```

And add a sentence after the Quick reference command block:

```
Use `-p/--project <id|path>` before any of `mounts`, `git-auth`, `open`,
`restart`, or `stop` to target another project (by path, container hash, or
name). Use `-g` before `mounts` to manage the always-on global volumes.
```

- [ ] **Step 2: Update the Upgrading section**

Replace the upgrade command:

```
claude-sandbox global mounts add npm-globals:/home/claude/.npm-globals  # opt the global config into the new volume
```

with:

```
claude-sandbox -g mounts add npm-globals:/home/claude/.npm-globals  # opt the global config into the new volume
```

- [ ] **Step 3: Verify no stale `global mounts` references remain**

```bash
grep -rn 'global mounts' README.md
```

Expected: no output (exit 1). If any remain, update them to `-g mounts`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README uses -g mounts and documents -p/--project"
```

---

## Final manual smoke test (on a host with fish + docker)

After all tasks, run the spec's smoke checklist against a real project:

- [ ] `claude-sandbox -g mounts add/list/remove/clear` matches old `global mounts` behavior.
- [ ] `claude-sandbox -p <existing-hash> mounts list` lists that container's project mounts.
- [ ] `claude-sandbox -p <path> git-auth show` reads the named project, not `pwd`.
- [ ] `claude-sandbox -p <hash> open` / `-p <path> restart` / `-p <hash> stop` operate on the named project.
- [ ] `claude-sandbox -p <hash>` (no subcommand) attaches that project's sandbox.
- [ ] Each error case from the spec produces the expected message and non-zero exit.
- [ ] Tab completion: `claude-sandbox -p <TAB>` offers container hashes and directories; `claude-sandbox -p <hash> <TAB>` offers subcommands; `claude-sandbox -g <TAB>` offers `mounts`; `claude-sandbox glo<TAB>` offers nothing.
