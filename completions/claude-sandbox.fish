# Tab completions for claude-sandbox

set -l subcommands stop list open git-auth mounts global

# No file completion at top level
complete -c claude-sandbox -f

# Top-level: --help and subcommands (only when no subcommand seen yet)
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -l help -d 'Show usage and exit'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a stop   -d 'Stop this project'\''s container'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a list   -d 'List all sandbox containers'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a open   -d 'Open VS Code for a sandbox by path or container name'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a git-auth -d 'Manage per-project git auth'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a mounts -d 'Manage per-project volume entries'
complete -c claude-sandbox \
    -n "not __fish_seen_subcommand_from $subcommands" \
    -a global -d 'Manage global configuration'

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

# open: completion source draws from existing sandbox containers
function __claude_sandbox_open_targets
    docker ps -a --filter "label=claude-sandbox.project" \
        --format '{{.Names}}\t{{.Label "claude-sandbox.project"}}\t{{.Status}}' 2>/dev/null \
        | while read -l line
            set -l parts (string split \t -- $line)
            set -l name $parts[1]
            set -l path $parts[2]
            set -l container_status $parts[3]
            printf '%s\t%s\n' $path $container_status
            printf '%s\t%s\n' $name "$path ($container_status)"
        end
end

complete -c claude-sandbox -f \
    -n "__fish_seen_subcommand_from open" \
    -a '(__claude_sandbox_open_targets)'

complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from open" \
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

# mounts actions (not under global)
set -l mount_actions add remove list clear
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global; and not __fish_seen_subcommand_from $mount_actions" \
    -a add    -d 'Add a volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global; and not __fish_seen_subcommand_from $mount_actions" \
    -a remove -d 'Remove a volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global; and not __fish_seen_subcommand_from $mount_actions" \
    -a list   -d 'List volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global; and not __fish_seen_subcommand_from $mount_actions" \
    -a clear  -d 'Clear all volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from global" \
    -l help -d 'Show usage'

# global → mounts → actions
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and not __fish_seen_subcommand_from mounts" \
    -a mounts -d 'Manage global volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and __fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a add    -d 'Add a global volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and __fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a remove -d 'Remove a global volume entry'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and __fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a list   -d 'List global volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global; and __fish_seen_subcommand_from mounts; and not __fish_seen_subcommand_from $mount_actions" \
    -a clear  -d 'Clear all global volume entries'
complete -c claude-sandbox \
    -n "__fish_seen_subcommand_from global" \
    -l help -d 'Show usage'
