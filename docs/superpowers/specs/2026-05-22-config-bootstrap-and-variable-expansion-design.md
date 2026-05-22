# Design: Config Bootstrap and Variable Expansion

**Date:** 2026-05-22

## Summary

Four changes to `claude-sandbox`:

1. Auto-create `configurations.yml` from `configurations.yml.template` on first use, with variables expanded at copy time.
2. Support `~`, `${WORKDIR}`, `${HOME}` as project keys in the template (expanded during bootstrap).
3. Add `configurations.yml` to `.gitignore`.
4. Rename `REPO_DIR` to `WORKDIR` in `Makefile`.

## 1. Bootstrap: Auto-create configurations.yml

**Trigger:** Lazy — any `claude-sandbox` command.

**Location:** `_sandbox_config_file` in `functions/claude-sandbox.fish`.

**Behavior:** If `configurations.yml` does not exist and `configurations.yml.template` does, copy the template and expand variables in place via `sed`. The resulting file has fully resolved absolute paths with no symbolic variables.

**Implementation:**

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

No other functions change. All read/write operations continue to use the file as-is.

## 2. Variable Support in Template

`configurations.yml.template` may use `${WORKDIR}`, `${HOME}`, and `~/` in both keys and values. These are expanded to absolute paths at bootstrap time. The live `configurations.yml` always contains absolute paths.

## 3. .gitignore

Add `configurations.yml` so user-specific config (project credentials, paths) is never committed.

## 4. Makefile: Rename REPO_DIR → WORKDIR

Rename the `REPO_DIR` variable to `WORKDIR` throughout `Makefile` (4 occurrences). Aligns the Makefile variable with the `${WORKDIR}` token used in the template.

## Files Changed

| File | Change |
|---|---|
| `functions/claude-sandbox.fish` | Update `_sandbox_config_file` to bootstrap from template |
| `.gitignore` | Add `configurations.yml` |
| `Makefile` | Rename `REPO_DIR` → `WORKDIR` |
| `configurations.yml.template` | No change (already uses `${WORKDIR}`) |
| `configurations.yml` | Add to `.gitignore`; generated from template on first run |
