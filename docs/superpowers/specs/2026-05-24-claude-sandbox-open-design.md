# `claude-sandbox open` Subcommand Design

**Date:** 2026-05-24
**Status:** Approved

## Problem

The bare `claude-sandbox` command always targets the current directory. To open VS Code against a different project's container, the user has to `cd` into that project first. `claude-sandbox list` shows what's running, but there's no command that takes an entry from that list and attaches VS Code to it.

## Goal

Add `claude-sandbox open <target>` so the user can launch any sandbox from anywhere, with tab completion driven by the existing container list.

---

## Command Surface

```
claude-sandbox open <target>
```

`<target>` is resolved in this order:

1. **Container name match.** If `docker inspect <target>` succeeds *and* the container carries a `claude-sandbox.project` label, treat `<target>` as a container hash name. Derive the project path from the label; derive the project name from `basename`. Run the launch flow against that path.
2. **Path fallback.** Otherwise, treat `<target>` as a project path. Resolve it with `realpath` (so relative paths and `.` work). Run the full launch flow against it — including the git-auth wizard and container creation if no container exists yet.

A missing `<target>` prints usage and exits non-zero. Passing `--help` prints the same usage block.

### Error cases

| Case | Behavior |
|---|---|
| `<target>` looks like `claude-sandbox-<hash>` but no such container exists | Fall through to path mode; `realpath` will fail and we surface the error. |
| `<target>` is a path that doesn't exist on disk | `realpath` fails; print the error and exit non-zero. |
| Container exists but lacks the `claude-sandbox.project` label | Treat as path mode (the name is just a string we couldn't claim). |

---

## Refactor: Extract `_sandbox_launch`

The launch flow at the bottom of `functions/claude-sandbox.fish` currently hard-codes `PROJECT_PATH=(pwd)`. Extract everything from the `docker info` check through the `code --folder-uri ...` call into a new helper:

```
_sandbox_launch <project_path>
```

The helper computes `project_name` from `basename`, computes `container_name` via `_sandbox_container_name`, and runs the existing git-auth resolution, container status switch, and VS Code launch.

Both the bare command and `open` then reduce to a single call:

- Bare command: `_sandbox_launch (pwd)`
- `open <path>`: `_sandbox_launch <resolved_path>`
- `open <hash>`: `_sandbox_launch (docker inspect --format '{{.Label "claude-sandbox.project"}}' <hash>)`

No behavioral change for the bare command.

---

## Tab Completion

A new fish helper feeds completions from `docker ps -a`:

```fish
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
```

`string split \t` is required because `read` splits on whitespace by default, which would break statuses like `Up 2 hours`.

This emits two completion candidates per container:
- The project path, described by its container status (e.g. `Up 2 hours`).
- The container hash name, described by the path plus status.

Wired into `completions/claude-sandbox.fish`:

```fish
# Add 'open' to the top-level subcommand list and the no-subcommand-seen list.
set -l subcommands stop list open git-auth mounts global

complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a open -d 'Open VS Code for a sandbox container'

# open: target completions
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from open" \
    -a '(__claude_sandbox_open_targets)' \
    -f

complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from open" \
    -l help -d 'Show usage'
```

The `-f` flag suppresses file completion so only docker-derived entries appear.

---

## Help Text

Top-level `claude-sandbox --help` gains one line:

```
  open <target>                     Open VS Code for a sandbox by path or container name
```

`claude-sandbox open --help`:

```
Usage: claude-sandbox open <target>

  Opens VS Code attached to a sandbox container.

  <target> may be either:
    - A project path (absolute or relative). Creates and starts a
      container if one does not exist for that path.
    - A container name (e.g. claude-sandbox-abc12345) from
      'claude-sandbox list'. Must already exist.

  Tab completion suggests both forms for every existing sandbox.
```

---

## Out of Scope

- Opening a brand-new project that has neither a container nor a configured path entry still works — the user types the path manually, no completion.
- Bulk operations (`open --all`, `open --running`) — separate feature if ever needed.
- Reading project paths from `configurations.yml` for completion of never-launched projects — explicitly chosen against; completion stays driven by `docker ps -a` so it matches `claude-sandbox list`.
