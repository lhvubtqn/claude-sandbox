function _sandbox_config_file
    set -l repo_dir (dirname (dirname (realpath (status filename))))
    set -l config $repo_dir/configurations.yml
    if not test -f $config
        set -l template $repo_dir/configurations.yml.template
        if test -f $template
            set -l tmp (mktemp)
            sed -e "s|\${WORKDIR}|$repo_dir|g" \
                -e "s|\${HOME}|$HOME|g" \
                -e "s|~/|$HOME/|g" \
                $template > $tmp
            and mv $tmp $config
        end
    end
    echo $config
end

function _sandbox_config_read_git_auth_type
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.type // empty' $f 2>/dev/null
end

function _sandbox_config_read_git_auth_path
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.path // empty' $f 2>/dev/null
end

function _sandbox_config_read_git_auth_prefer_ssh
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.prefer_ssh // empty' $f 2>/dev/null
end

function _sandbox_config_read_git_auth_identity_name
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.identity.name // empty' $f 2>/dev/null
end

function _sandbox_config_read_git_auth_identity_email
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].git_auth.identity.email // empty' $f 2>/dev/null
end

function _sandbox_config_write_git_auth_ssh
    # Usage: _sandbox_config_write_git_auth_ssh <project_path> <key_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg k $argv[2] \
        '.projects[$p].git_auth = {"type": "ssh", "path": $k, "prefer_ssh": true}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_write_git_auth_pat
    # Usage: _sandbox_config_write_git_auth_pat <project_path> <token_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg t $argv[2] \
        '.projects[$p].git_auth = {"type": "pat", "path": $t}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_write_git_auth_none
    # Usage: _sandbox_config_write_git_auth_none <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] \
        '.projects[$p].git_auth = {"type": "none"}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_write_git_auth_identity
    # Usage: _sandbox_config_write_git_auth_identity <project_path> <name> <email>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg n $argv[2] --arg e $argv[3] \
        '.projects[$p].git_auth.identity = {"name": $n, "email": $e}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_delete
    # Usage: _sandbox_config_delete <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] 'del(.projects[$p].git_auth)' $f > $tmp
    and mv $tmp $f
end

function _sandbox_mounts_list
    set -l f (_sandbox_config_file)
    test -f $f; or return
    yq -r --arg p $argv[1] '.projects[$p].container.volumes // [] | .[]' $f 2>/dev/null
end

function _sandbox_mounts_add
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.projects[$p].container.volumes = ((.projects[$p].container.volumes // []) + [$m])' $f > $tmp
    and mv $tmp $f
end

function _sandbox_mounts_remove
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l count (yq -r --arg p $argv[1] '.projects[$p].container.volumes | length' $f 2>/dev/null)
    test "$count" -gt 0 2>/dev/null; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.projects[$p].container.volumes = [(.projects[$p].container.volumes // [])[] | select(. != $m)]' $f > $tmp
    and mv $tmp $f
end

function _sandbox_mounts_clear
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] 'del(.projects[$p].container.volumes)' $f > $tmp
    and mv $tmp $f
end

function _sandbox_global_mounts_list
    set -l f (_sandbox_config_file)
    test -f $f; or return
    yq -r '.global.container.volumes // [] | .[]' $f 2>/dev/null
end

function _sandbox_global_mounts_add
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg m $argv[1] \
        '.global.container.volumes = ((.global.container.volumes // []) + [$m])' $f > $tmp
    and mv $tmp $f
end

function _sandbox_global_mounts_remove
    # Usage: _sandbox_global_mounts_remove <mount_spec>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg m $argv[1] \
        '.global.container.volumes = [(.global.container.volumes // [])[] | select(. != $m)]' $f > $tmp
    and mv $tmp $f
end

function _sandbox_global_mounts_clear
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y 'del(.global.container.volumes)' $f > $tmp
    and mv $tmp $f
end

function _sandbox_expand_vars
    # Expands ${WORKDIR}, ${HOME}, and leading ~ in a path string.
    set -l workdir (dirname (_sandbox_config_file))
    set -l result $argv[1]
    set result (string replace -- '${WORKDIR}' $workdir $result)
    set result (string replace -- '${HOME}' $HOME $result)
    set result (string replace -r '^~/' $HOME/ $result)
    echo $result
end

function _sandbox_container_name
    # Usage: _sandbox_container_name <absolute_project_path>
    set -l hash (printf '%s' $argv[1] | sha256sum | cut -c1-8)
    echo "claude-sandbox-$hash"
end

function _sandbox_render_config
    # Usage: _sandbox_render_config <project_path>
    # Emits a canonical, sorted snapshot of the effective container config as
    # tab-delimited "category<TAB>value" lines. Single source of truth for drift
    # detection. Must mirror the args _sandbox_docker_run actually applies.
    set -l f (_sandbox_config_file)
    test -f $f; or return
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
        set -l prefer_ssh (_sandbox_config_read_git_auth_prefer_ssh $p)
        if test "$prefer_ssh" = true
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

function _sandbox_docker_run
    # Usage: _sandbox_docker_run <container_name> <project_path> <project_name>
    set -l container_name $argv[1]
    set -l project_path $argv[2]
    set -l project_name $argv[3]
    set -l f (_sandbox_config_file)

    # Resolve image (project overrides global)
    set -l image (yq -r --arg p $project_path \
        '(.projects[$p].container.image // .global.container.image // "claude-sandbox")' $f)

    set -l args -d \
        --name $container_name \
        --hostname claude-sandbox \
        --label "claude-sandbox.project=$project_path"

    # security_opt: global then project
    for opt in (yq -r --arg p $project_path \
        '((.global.container.security_opt // []) + (.projects[$p].container.security_opt // [])) | .[]' $f 2>/dev/null)
        set args $args --security-opt $opt
    end

    # extra_hosts: global then project
    for host in (yq -r --arg p $project_path \
        '((.global.container.extra_hosts // []) + (.projects[$p].container.extra_hosts // [])) | .[]' $f 2>/dev/null)
        set args $args --add-host $host
    end

    # volumes: global then project, with variable expansion
    for vol in (yq -r --arg p $project_path \
        '((.global.container.volumes // []) + (.projects[$p].container.volumes // [])) | .[]' $f 2>/dev/null)
        set args $args -v (_sandbox_expand_vars $vol)
    end

    # Git auth injection
    set -l auth_type (_sandbox_config_read_git_auth_type $project_path)
    set args $args -e "SANDBOX_GIT_AUTH_TYPE=$auth_type"
    if test "$auth_type" = ssh; or test "$auth_type" = pat
        set -l creds_path (_sandbox_expand_vars (_sandbox_config_read_git_auth_path $project_path))
        set args $args -v "$creds_path:/home/claude/.gitcreds:ro"
    end
    if test "$auth_type" = ssh
        set -l prefer_ssh (_sandbox_config_read_git_auth_prefer_ssh $project_path)
        if test "$prefer_ssh" = true
            set args $args -e "SANDBOX_GIT_PREFER_SSH=1"
        end
    end
    set -l id_name (_sandbox_config_read_git_auth_identity_name $project_path)
    set -l id_email (_sandbox_config_read_git_auth_identity_email $project_path)
    if test -n "$id_name"
        set args $args -e "SANDBOX_GIT_NAME=$id_name"
    end
    if test -n "$id_email"
        set args $args -e "SANDBOX_GIT_EMAIL=$id_email"
    end

    # Project workspace bind mount
    set args $args -v "$project_path:/workspace/$project_name"

    # Config snapshot label for drift detection
    set -l config_snapshot (_sandbox_render_config $project_path | base64 | tr -d '\n')
    set args $args --label "claude-sandbox.config-snapshot=$config_snapshot"

    set args $args \
        --workdir /workspace/$project_name \
        --entrypoint /entrypoint.sh

    docker run $args $image sleep infinity
end

function _sandbox_copy_pubkey
    # Usage: _sandbox_copy_pubkey <pubkey_file_path>
    if uname -r | grep -qi microsoft
        cat $argv[1] | clip.exe
        and echo "Public key copied to clipboard."
    else
        echo "Note: clipboard not available. Public key:"
        cat $argv[1]
    end
end


function _sandbox_git_auth_wizard
    # Usage: _sandbox_git_auth_wizard <project_path> <project_name>
    set -l project_path $argv[1]
    set -l project_name $argv[2]

    echo ""
    echo "No git credentials configured for this project. How would you like to authenticate?"
    echo ""
    echo "  1. SSH [Enter]"
    echo "  2. Personal Access Token (PAT)"
    echo "  3. Skip"
    echo ""
    read -P "Choice [default=1]: " choice
    or return 1
    if test -z "$choice"
        set choice 1
    end

    switch $choice
        case 1
            echo "Generate a new SSH key or use an existing one?"
            echo "  1. Generate a new key"
            echo "  2. Use an existing key"
            echo ""
            read -P "Choice [default=2]: " ssh_choice
            or return 1
            if test -z "$ssh_choice"
                set ssh_choice 2
            end

            set -l default_path $HOME/.ssh/id_ed25519_$project_name
            switch $ssh_choice
                case 1
                    read -P "Key path [$default_path]: " key_path
                    or return 1
                    if test -z "$key_path"
                        set key_path $default_path
                    else
                        set key_path (_sandbox_expand_vars $key_path)
                    end

                    ssh-keygen -t ed25519 -f $key_path -C "$project_name deploy key" -N ""
                    or return 1

                    echo ""
                    echo "Key generated at $key_path"
                    _sandbox_copy_pubkey "$key_path.pub"
                    echo ""
                    echo "GitHub : repo Settings -> Deploy keys -> Add deploy key  (enable \"Allow write access\" if needed)"
                    echo "GitLab : repo Settings -> Repository -> Deploy keys"
                    echo ""
                    read -P "Press Enter when done to launch the sandbox..." _dummy
                    or return 1

                case 2
                    read -P "SSH key path: " key_path
                    or return 1
                    set key_path (_sandbox_expand_vars $key_path)
                    if not test -f $key_path
                        echo "Error: key file not found: $key_path"
                        return 1
                    end

                case '*'
                    echo "Error: invalid choice '$ssh_choice'"
                    return 1
            end

            _sandbox_config_write_git_auth_ssh $project_path $key_path

        case 2
            read -P "Token file path: " token_path
            or return 1
            set token_path (_sandbox_expand_vars $token_path)
            if not test -f $token_path
                echo "Error: file not found: $token_path"
                return 1
            end
            _sandbox_config_write_git_auth_pat $project_path $token_path

        case 3
            _sandbox_config_write_git_auth_none $project_path
            return 0

        case '*'
            echo "Error: invalid choice '$choice'"
            return 1
    end

    # Identity step (SSH and PAT only)
    set -l default_name (git config --global user.name 2>/dev/null)
    set -l default_email (git config --global user.email 2>/dev/null)

    echo ""
    echo "Git identity for this project:"

    set -l name_prompt "  Name"
    if test -n "$default_name"
        set name_prompt "$name_prompt [$default_name]"
    end
    read -P "$name_prompt: " id_name
    or return 1
    if test -z "$id_name"
        set id_name $default_name
    end

    set -l email_prompt "  Email"
    if test -n "$default_email"
        set email_prompt "$email_prompt [$default_email]"
    end
    read -P "$email_prompt: " id_email
    or return 1
    if test -z "$id_email"
        set id_email $default_email
    end

    if test -n "$id_name"; or test -n "$id_email"
        _sandbox_config_write_git_auth_identity $project_path $id_name $id_email
    end
end

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
        or return 1
    end
    if test -n "$st"
        docker rm $container_name > /dev/null
        or return 1
    end
    _sandbox_docker_run $container_name $project_path $project_name
end

function _sandbox_launch
    # Usage: _sandbox_launch <project_path>
    set -l PROJECT_PATH $argv[1]
    set -l PROJECT_NAME (basename $PROJECT_PATH)

    _sandbox_preflight $PROJECT_PATH; or return 1

    set -l container_name (_sandbox_container_name $PROJECT_PATH)
    set -l container_status (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)

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

function claude-sandbox
    set -l PROJECT_PATH (pwd)
    set -l PROJECT_NAME (basename $PROJECT_PATH)

    # --- top-level --help ---
    if contains -- --help $argv; and test (count $argv) -eq 1
        echo "Usage: claude-sandbox [--help]"
        echo "       claude-sandbox <subcommand> [--help]"
        echo ""
        echo "Subcommands:"
        printf "  %-34s%s\n" "(no args)"            "Launch sandbox for current project"
        printf "  %-34s%s\n" "stop [--rm]"           "Stop this project's container; --rm also removes it"
        printf "  %-34s%s\n" "list"                  "List all sandbox containers"
        printf "  %-34s%s\n" "open <target>"         "Open VS Code for a sandbox by path or container name"
        printf "  %-34s%s\n" "git-auth <action>"     "Manage per-project git auth"
        printf "  %-34s%s\n" "mounts <action>"       "Manage per-project volume entries"
        printf "  %-34s%s\n" "global mounts <action>" "Manage always-on global volume entries"
        echo ""
        echo "Run 'claude-sandbox <subcommand> --help' for subcommand usage."
        return 0
    end

    # --- global subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = global
        if contains -- --help $argv
            echo "Usage: claude-sandbox global mounts {add <spec>|remove <spec>|list|clear}"
            echo ""
            printf "  %-24s%s\n" "add <spec>"    "Add a volume entry applied to every container"
            printf "  %-24s%s\n" "remove <spec>" "Remove a global volume entry"
            printf "  %-24s%s\n" "list"          "Show all global volume entries"
            printf "  %-24s%s\n" "clear"         "Remove all global volume entries"
            return 0
        end
        if test (count $argv) -lt 3; or test "$argv[2]" != mounts
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

    # --- stop subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = stop
        if contains -- --help $argv
            echo "Usage: claude-sandbox stop [--rm]"
            echo ""
            echo "  Stops the container for the current project."
            echo "  --rm    Also remove the container after stopping."
            return 0
        end
        set -l remove false
        if contains -- --rm $argv
            set remove true
        end
        set -l container_name (_sandbox_container_name $PROJECT_PATH)
        if not docker inspect $container_name > /dev/null 2>&1
            echo "No container found for $PROJECT_PATH"
            return 1
        end
        set -l stop_status (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)
        if test "$stop_status" = running; or test "$stop_status" = paused; or test "$stop_status" = restarting
            docker stop $container_name
            or return 1
        else
            echo "Container is already stopped."
        end
        if test "$remove" = true
            docker rm $container_name
            or return 1
        end
        return
    end

    # --- list subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = list
        if contains -- --help $argv
            echo "Usage: claude-sandbox list"
            echo ""
            echo "  Lists all claude-sandbox containers and their project paths."
            return 0
        end
        docker ps -a \
            --filter "label=claude-sandbox.project" \
            --format "table {{.Names}}\t{{.Label \"claude-sandbox.project\"}}\t{{.Status}}"
        return
    end

    # --- git-auth subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = git-auth
        set -l action $argv[2]
        if contains -- --help $argv
            echo "Usage: claude-sandbox git-auth {set|show|clear|list}"
            echo ""
            printf "  %-22s%s\n" "set"   "Configure git credentials (SSH or PAT)"
            printf "  %-22s%s\n" "show"  "Print saved git auth for current project"
            printf "  %-22s%s\n" "clear" "Remove saved git auth (will prompt on next launch)"
            printf "  %-22s%s\n" "list"  "List all saved project git auth"
            return 0
        end
        switch $action
            case set
                _sandbox_git_auth_wizard $PROJECT_PATH $PROJECT_NAME
            case show
                set -l t (_sandbox_config_read_git_auth_type $PROJECT_PATH)
                if test -z "$t"
                    echo "No git auth configured for $PROJECT_PATH"
                else
                    echo "type: $t"
                    if test "$t" = ssh; or test "$t" = pat
                        echo "path: "(_sandbox_config_read_git_auth_path $PROJECT_PATH)
                    end
                    if test "$t" = ssh
                        echo "prefer_ssh: "(_sandbox_config_read_git_auth_prefer_ssh $PROJECT_PATH)
                    end
                    set -l n (_sandbox_config_read_git_auth_identity_name $PROJECT_PATH)
                    set -l e (_sandbox_config_read_git_auth_identity_email $PROJECT_PATH)
                    if test -n "$n"; or test -n "$e"
                        echo "identity:"
                        echo "  name: $n"
                        echo "  email: $e"
                    end
                end
            case clear
                _sandbox_config_delete $PROJECT_PATH
                echo "Cleared git auth for $PROJECT_PATH (will prompt on next launch)"
            case list
                set -l f (_sandbox_config_file)
                if not test -f $f
                    echo "No git auth configured."
                    return
                end
                yq -r '(.projects // {}) | to_entries[] | select(.value.git_auth != null) | "\(.key)\n  type: \(.value.git_auth.type)" + (if .value.git_auth.path then "\n  path: \(.value.git_auth.path)" else "" end) + (if .value.git_auth.identity then "\n  name: \(.value.git_auth.identity.name)\n  email: \(.value.git_auth.identity.email)" else "" end)' $f
            case '*'
                echo "Usage: claude-sandbox git-auth {set|show|clear|list}"
                return 1
        end
        return
    end

    # --- mounts subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = mounts
        set -l action $argv[2]
        if contains -- --help $argv
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
        end
        switch $action
            case add
                if test (count $argv) -lt 3
                    echo "Usage: claude-sandbox mounts add <source>:<target>[:<options>]"
                    return 1
                end
                _sandbox_mounts_add $PROJECT_PATH $argv[3]
                echo "Added mount for $PROJECT_PATH: $argv[3]"
            case remove
                if test (count $argv) -lt 3
                    echo "Usage: claude-sandbox mounts remove <source>:<target>[:<options>]"
                    return 1
                end
                _sandbox_mounts_remove $PROJECT_PATH $argv[3]
                echo "Removed mount for $PROJECT_PATH: $argv[3]"
            case list
                set -l mounts (_sandbox_mounts_list $PROJECT_PATH)
                if test (count $mounts) -eq 0
                    echo "No extra mounts configured for $PROJECT_PATH"
                else
                    for m in $mounts
                        echo $m
                    end
                end
            case clear
                _sandbox_mounts_clear $PROJECT_PATH
                echo "Cleared all mounts for $PROJECT_PATH"
            case '*'
                echo "Usage: claude-sandbox mounts {add <spec>|remove <spec>|list|clear}"
                return 1
        end
        return
    end

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
            echo "    - A container name (e.g. claude-sandbox-abc12345) or its"
            echo "      bare hash (abc12345) from 'claude-sandbox list'. Must"
            echo "      already exist."
            echo ""
            echo "  Tab completion lists the hash and path for every existing sandbox."
            return 0
        end
        if test (count $argv) -lt 2
            echo "Usage: claude-sandbox open <target>"
            return 1
        end
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
    end

    # --- launch flow ---
    _sandbox_launch $PROJECT_PATH
end
