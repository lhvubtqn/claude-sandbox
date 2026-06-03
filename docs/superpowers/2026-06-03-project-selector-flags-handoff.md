# Handoff — `-p/--project` selector & `-g` global flag

**Date:** 2026-06-03
**Status:** Implemented, reviewed, and merged to `master` locally. Not pushed. Runtime smoke test pending (needs host with fish + docker + yq).

## TL;DR

A universal `-p/--project <id|path>` selector and a `-g/--global` flag were added to the `claude-sandbox` fish CLI; the old `global` subcommand keyword was removed. All work is committed on `master` (fast-forward merge of `feat/project-selector-flags`, branch deleted). Static `fish -n` passes on both fish files. The docker-backed behavior has NOT been exercised yet — that's the main thing to do on the host.

## Where things stand (git)

- Current branch: `master`.
- `master` is **ahead of `origin/master` by 9 commits** — 2 docs (spec + plan) + 7 implementation:
  ```
  7374a8d docs: README uses -g mounts and documents -p/--project
  90f6652 feat: completions for -p/-g flags; remove global keyword
  4432267 docs: update help text for -p/--project and -g flags
  69bac78 feat: honor -p/--project in open and restart
  360b1ac feat: honor -p/--project in git-auth and stop
  5d8a765 feat: add -p/-g flag parser, route -g mounts, drop global subcommand
  faa49b4 refactor: extract _sandbox_resolve_target from open/restart
  8ec4daf docs: implementation plan for -p/--project and -g flags
  306ff8d docs: spec for -p/--project selector and -g global flag
  ```
- Files changed by the feature: `functions/claude-sandbox.fish`, `completions/claude-sandbox.fish`, `README.md`.
- **Unrelated, pre-existing:** `Dockerfile` has an uncommitted modification that predates this work — left untouched. Decide separately whether to keep/commit/discard it.

## What to do on the host

### 1. Reload the updated fish files into your shell
The functions/completions changed, so an open fish session still has the old versions:
```fish
source functions/claude-sandbox.fish
source completions/claude-sandbox.fish
# or just open a new shell if these are autoloaded from your fish config
```

### 2. Run the smoke checklist (docker + yq + fish required)

Reference: `docs/superpowers/specs/2026-06-03-project-selector-flags-design.md` (Testing section) and the plan's final checklist in `docs/superpowers/plans/2026-06-03-project-selector-flags.md`.

Global mounts (replaces old `global mounts ...`):
- [ ] `claude-sandbox -g mounts add testvol:/tmp/test` → "Added global mount: ..."
- [ ] `claude-sandbox -g mounts list` → shows it
- [ ] `claude-sandbox -g mounts remove testvol:/tmp/test` → removed
- [ ] `claude-sandbox -g mounts clear`

Per-project via `-p` (path works even with no container yet):
- [ ] `claude-sandbox -p /some/existing/dir mounts add foo:/bar` then `... mounts list` → keyed by the realpath'd path
- [ ] `claude-sandbox -p <hash> mounts list` → lists that existing container's project mounts
- [ ] `claude-sandbox -p <path|hash> git-auth show` → reads the named project, not `pwd`
- [ ] `claude-sandbox -p <hash> open` → attaches that project
- [ ] `claude-sandbox -p <path> restart` → recreates that project's container
- [ ] `claude-sandbox -p <hash> stop` → stops that project's container
- [ ] `claude-sandbox -p <hash>` (no subcommand) → launches/attaches X (same as `open X`)

Error cases (should print the message and exit non-zero):
- [ ] `claude-sandbox -g -p /tmp mounts list` → "Error: -g and -p are mutually exclusive."
- [ ] `claude-sandbox -g list` → "Error: -g is only valid with 'mounts'."
- [ ] `claude-sandbox -p list mounts list` → "Error: -p requires a project path or container reference."
- [ ] `claude-sandbox -p /tmp list` → "Error: list is cross-project; -p/-g not applicable."
- [ ] `claude-sandbox -p /no/such/xyz mounts list` → "Error: '...' is neither an existing sandbox container nor a valid path."
- [ ] `claude-sandbox global mounts list` → `global` is no longer a subcommand (falls through to launch flow / docker preflight)

Backward-compat (must still work):
- [ ] `claude-sandbox open <hash>` and `claude-sandbox restart <path>` (positional, no `-p`)
- [ ] plain `claude-sandbox` and `claude-sandbox mounts list` (operate on current dir)

Tab completion:
- [ ] `claude-sandbox -p <TAB>` → offers container hashes and directories
- [ ] `claude-sandbox -p <hash> <TAB>` → offers subcommands
- [ ] `claude-sandbox -g <TAB>` → offers only `mounts`
- [ ] `claude-sandbox glo<TAB>` → offers nothing (no `global`)

### 3. Push when satisfied
```bash
git push          # publishes the 9 commits to origin/master
```
(If you prefer a PR instead of pushing straight to `master`, create a branch from these commits first.)

## Known minor / optional polish (all non-blocking, deferred by design)

From the final whole-branch review — none affect runtime correctness:
1. Per-subcommand `--help` for `git-auth`/`stop`/`open`/`restart` don't mention `-p` (the top-level `--help` documents the full scope). `mounts --help` does show `[-p <project>|-g]`.
2. `_sandbox_resolve_target` uses `realpath $value` without `--`; a value starting with `-` is misread but still yields a sane "neither container nor valid path" error. Optional hardening: `realpath -- $value`.
3. Wording nit: completions say "Manage per-project volume entries" while function help says "Manage current project's volume entries".
4. Completions don't model invalid flag combos (e.g. `list` is still suggested after `-p`, and the opposite flag is still offered after one is typed) — common fish behavior.
5. A directory literally named like a subcommand (`mounts`, `open`, …) can't be targeted by bare name via `-p` (guard rejects it); use `./mounts` or an absolute path. Intentional ambiguity-avoidance.

## Design decisions (locked, from the spec)

- `open`/`restart` accept BOTH `-p X` and the existing positional target (backward compatible).
- `global` keyword fully removed (hard replace, not aliased).
- `-p` resolves a path (realpath, valid pre-container) OR a container hash/name (needs existing container).
- `-p` applies to: mounts, git-auth, open, restart, stop. `list` is cross-project (rejects `-p`/`-g`).
- Flags appear BEFORE the subcommand only.

## Reference docs
- Spec: `docs/superpowers/specs/2026-06-03-project-selector-flags-design.md`
- Plan: `docs/superpowers/plans/2026-06-03-project-selector-flags.md`
