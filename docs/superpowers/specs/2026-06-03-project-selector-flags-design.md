# Project-selector flags: `-p/--project` and `-g`

**Date:** 2026-06-03
**Status:** Approved design

## Summary

Reshape the `claude-sandbox` CLI argument grammar so a single project can be
targeted from anywhere via a universal `-p/--project <id|path>` flag, and so the
global volume configuration is reached through `-g/--global` instead of the
`global` subcommand keyword.

Today most subcommands implicitly operate on the current directory (`pwd`), and
global volumes are managed through a dedicated `global mounts ...` subcommand.
After this change:

```
claude-sandbox mounts <cmd>            # current project (unchanged)
claude-sandbox -p <id|path> mounts <cmd>   # a specific project
claude-sandbox -g mounts <cmd>         # global volumes (replaces `global mounts`)
```

`-p/--project` also applies to `git-auth`, `open`, `restart`, and `stop`.

## Decisions (locked)

1. **`open`/`restart` keep their positional target.** `-p X open` and the
   existing `open X` both work; `-p` is an alternative spelling, not a
   replacement. No breakage to existing usage.
2. **`global` keyword is removed.** Only `-g`/`--global` works. `global` becomes
   an unknown subcommand.
3. **`-p` resolution accepts path + hash/name; a path works pre-container.** An
   absolute/relative path is `realpath`'d and is valid even when no container
   exists yet (so mounts/git-auth can be pre-seeded before first launch). A bare
   hash or full container name resolves only when a container already exists.
4. **`-p` applies to `mounts`, `git-auth`, `open`, `restart`, `stop`.** `list`
   is inherently cross-project and does not accept `-p`/`-g`.
5. **Flags appear before the subcommand only.** e.g. `claude-sandbox -p X mounts
   add ...`. Trailing flags are not supported.

## Architecture

A small **front-door parsing layer** is added at the top of the `claude-sandbox`
function, before any subcommand dispatch. It consumes leading flags, resolves a
single target, strips the flags from `argv`, and lets the existing
subcommand chain run with minimal change — each project-scoped subcommand reads
the resolved `TARGET_PATH` instead of calling `pwd` directly.

### Resolution helper

Extract the target-resolution logic currently **duplicated** inside the `open`
and `restart` subcommands into a shared function:

```
_sandbox_resolve_target <value>
    # Try <value> and claude-sandbox-<value> as container references; read the
    # claude-sandbox.project label. On miss, fall back to `realpath <value>`.
    # Echo the resolved absolute path, or nothing (return non-zero) on failure.
```

`open` and `restart` are refactored to call `_sandbox_resolve_target`, removing
the duplicated inline loops. The new `-p` parser uses the same helper.

Resolution semantics:

- A container hash (`abc12345`) or full name (`claude-sandbox-abc12345`) →
  resolves to the labeled project path **only if that container exists**.
- A path (absolute or relative) → `realpath`'d; valid even with **no container**.

### Parsing layer behavior

After parsing leading flags:

- `-g`/`--global` present → **global mode** (no project path).
- `-p`/`--project <value>` present → `TARGET_PATH = _sandbox_resolve_target <value>`.
- Neither present → `TARGET_PATH = pwd` (today's behavior, unchanged).

The flags are stripped so that `argv[1]` is the subcommand for the existing
dispatch chain.

## Per-command behavior

| Invocation | Behavior |
|---|---|
| `mounts <action>` | project mounts for **pwd** (unchanged) |
| `-p X mounts <action>` | project mounts for **X** |
| `-g mounts <action>` | **global** mounts (replaces `global mounts ...`) |
| `git-auth <action>` | git-auth for **pwd** (unchanged) |
| `-p X git-auth <action>` | git-auth for **X** |
| `stop [--rm]` | stop pwd's container (unchanged) |
| `-p X stop [--rm]` | stop **X**'s container |
| `open [target]` | unchanged (positional) |
| `-p X open` | open **X** (equivalent to `open X`) |
| `restart [target]` | unchanged (positional) |
| `-p X restart` | restart **X** |
| `-p X` *(no subcommand)* | launch/attach **X** (same as `open X`) |
| `list` | cross-project; unchanged |

The `mounts` handler gains one branch: in global mode it routes to the
`_sandbox_global_mounts_*` helpers; otherwise it uses the `_sandbox_mounts_*`
helpers with `TARGET_PATH`. The standalone `global` subcommand block is
**deleted** entirely.

For `open`/`restart`: if `-p` supplied a target, use `TARGET_PATH`; otherwise
fall back to the positional argument (existing logic). Both spellings are
supported; supplying both `-p` and a positional is not expected — `-p` wins.

## Validation & error handling

| Condition | Error message |
|---|---|
| `-g` with a non-`mounts` subcommand | `Error: -g is only valid with 'mounts'.` |
| `-g` and `-p` both given | `Error: -g and -p are mutually exclusive.` |
| `-p`/`-g` with `list` | `Error: list is cross-project; -p/-g not applicable.` |
| `-p` with no value (missing, or next token is a known subcommand) | `Error: -p requires a project path or container reference.` |
| `-p <value>` resolves to nothing | `Error: '<value>' is neither an existing sandbox container nor a valid path.` |

All error cases return non-zero.

## Completions

`completions/claude-sandbox.fish` is reworked:

- Drop `global` from `$subcommands` and remove the entire
  `global → mounts → actions` completion block.
- Add leading flags at top level (offered when no subcommand has been seen):
  - `-p/--project`, declared with `-r` (requires an argument). Its argument
    completes from the existing `__claude_sandbox_open_targets` source
    (`hash<TAB>path`) **plus directory completion**, so both existing container
    refs and not-yet-launched paths complete.
  - `-g/--global` as a flag.
- Because `-p` is `-r`, fish treats the following token as the flag's value, so
  the existing `not __fish_seen_subcommand_from $subcommands` conditions keep
  firing and subcommands still complete after `-p X`.
- After `-g`, restrict subcommand completion to `mounts` only.
- `mounts`/`git-auth` action completions are unchanged — they key off
  `__fish_seen_subcommand_from`, which still holds with a leading `-p X`.

## Docs & help text

- **Top-level `--help`:** replace the `global mounts <action>` line with
  `-g mounts <action>`; add a line documenting the `-p/--project <id|path>`
  selector and the subcommands that honor it.
- **`mounts --help`:** note it targets the current project (or the `-p`
  project), and that `-g mounts ...` manages global volumes.
- **Delete** the `global` subcommand's `--help` block.
- **README.md:** update Quick reference and Upgrading sections —
  `claude-sandbox global mounts add ...` becomes `claude-sandbox -g mounts add
  ...`; mention `-p` for operating on other projects.

## Testing / verification

No automated test harness exists in this repo (consistent with every prior
feature). Verification is a manual smoke checklist:

- `-g mounts add/list/remove/clear` behaves identically to the old
  `global mounts ...`.
- `-p <path> mounts add/list` against a project with no container (config is
  written, keyed by the realpath'd path).
- `-p <hash> mounts list` against an existing container.
- `-p <path|hash> git-auth show/set/clear`.
- `-p <hash> open`, `-p <path> restart`, `-p <hash> stop` operate on the named
  project, not `pwd`.
- `-p X` with no subcommand launches/attaches X.
- Each error case above produces the expected message and non-zero exit.
- Tab completion: `-p ` offers container hashes and directories; subcommands
  complete after `-p X`; `-g ` offers only `mounts`; `global` no longer
  completes.

## Out of scope

- A global git-auth concept (`-g git-auth`) — git auth remains per-project only.
- Trailing/interleaved flag positions.
- Converting the CLI to fish `argparse` wholesale.
- Any new named volumes or container behavior.
