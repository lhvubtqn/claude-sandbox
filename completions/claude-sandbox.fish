# Tab completions for claude-sandbox

# Clear any previously-registered rules so re-sourcing this file doesn't stack
# stale completions (e.g. when $subcommands changes between versions).
complete -c claude-sandbox -e

set -l subcommands stop list open restart git-auth mounts

# No file completion at top level
complete -c claude-sandbox -f

# Top-level: --help and subcommands (only when no subcommand seen yet)
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -l help -d 'Show usage and exit'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands; and not __fish_seen_argument -s g -l global" \
    -a stop   -d 'Stop this project'\''s container'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands; and not __fish_seen_argument -s g -l global" \
    -a list   -d 'List all sandbox containers'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands; and not __fish_seen_argument -s g -l global" \
    -a open   -d 'Open VS Code for a sandbox by path or container name'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands; and not __fish_seen_argument -s g -l global" \
    -a restart -d 'Recreate a sandbox with current config and reattach'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands; and not __fish_seen_argument -s g -l global" \
    -a git-auth -d 'Manage per-project git auth'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a mounts -d 'Manage per-project volume entries'

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

# stop
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from stop" \
    -l rm   -d 'Also remove the container after stopping'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from stop" \
    -l help -d 'Show usage'

# list
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from list" \
    -l help -d 'Show usage'

# open: completion source draws from existing sandbox containers.
# We complete on the bare hash rather than the full container name: every
# container shares the "claude-sandbox-" prefix, which fish elides to "…-" in
# the pager (it hides prefixes common to all candidates). Completing on the
# hash sidesteps that — nothing gets clipped — and the path shown alongside
# makes each entry recognizable. `open` accepts the bare hash (see function).
function __claude_sandbox_open_targets
    docker ps -a --filter "label=claude-sandbox.project" \
        --format '{{.Names}}\t{{.Label "claude-sandbox.project"}}' 2>/dev/null \
        | while read -l line
            set -l parts (string split \t -- $line)
            set -l hash (string replace -- 'claude-sandbox-' '' $parts[1])
            set -l path $parts[2]
            printf '%s\t%s\n' $hash $path
        end
end

complete -c claude-sandbox -f \
    -n "__fish_seen_subcommand_from open" \
    -a '(__claude_sandbox_open_targets)'

complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from open" \
    -l help -d 'Show usage'

complete -c claude-sandbox -f \
    -n "__fish_seen_subcommand_from restart" \
    -a '(__claude_sandbox_open_targets)'

complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from restart" \
    -l help -d 'Show usage'

# git-auth actions
set -l git_auth_actions set show clear list
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth; and not __fish_seen_subcommand_from $git_auth_actions" \
    -a set   -d 'Configure git credentials (SSH or PAT)'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth; and not __fish_seen_subcommand_from $git_auth_actions" \
    -a show  -d 'Show current git auth'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth; and not __fish_seen_subcommand_from $git_auth_actions" \
    -a clear -d 'Remove saved git auth'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth; and not __fish_seen_subcommand_from $git_auth_actions" \
    -a list  -d 'List all project git auth'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from git-auth" \
    -l help -d 'Show usage'

# mounts actions
set -l mount_actions add remove list clear
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a add    -d 'Add a volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a remove -d 'Remove a volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a list   -d 'List volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a clear  -d 'Clear all volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts" \
    -l help -d 'Show usage'
