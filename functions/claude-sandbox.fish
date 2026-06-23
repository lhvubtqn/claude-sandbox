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

function _sandbox_config_read_ui_mode
    # Returns the project's ui_mode, defaulting to "none". Raw value (validation
    # happens where it's used, so a hand-edited typo fails loudly at launch).
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo none; return; end
    yq -r --arg p $argv[1] '.projects[$p].ui_mode // "none"' $f 2>/dev/null
end

function _sandbox_config_write_ui_mode
    # Usage: _sandbox_config_write_ui_mode <project_path> <mode>
    # mode=none deletes the key to keep config tidy; any other value is stored.
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    if test "$argv[2]" = none
        yq -y --arg p $argv[1] \
            'if .projects[$p] then del(.projects[$p].ui_mode) else . end' $f > $tmp
    else
        yq -y --arg p $argv[1] --arg m $argv[2] \
            '.projects[$p].ui_mode = $m' $f > $tmp
    end
    and mv $tmp $f
end

function _sandbox_config_read_network
    # Usage: _sandbox_config_read_network <project_path>
    # Project-level network overrides global; returns empty when unset.
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].container.network // .global.container.network // empty' $f 2>/dev/null
end

function _sandbox_config_write_network
    # Usage: _sandbox_config_write_network <project_path> <network_name>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg n $argv[2] \
        '.projects[$p].container.network = $n' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_clear_network
    # Usage: _sandbox_config_clear_network <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] \
        'if .projects[$p].container then del(.projects[$p].container.network) else . end' $f > $tmp
    and mv $tmp $f
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

    # environment: global then project, sorted. Accepts docker-compose's map
    # (KEY: value) or list (- KEY=value) form; both normalize to KEY=value.
    for env in (yq -r --arg p $p \
        'def norm: if type=="object" then (to_entries|map("\(.key)=\(.value)")) elif type=="array" then . else [] end; ((.global.container.environment | norm) + (.projects[$p].container.environment | norm)) | .[]' $f 2>/dev/null | sort)
        printf 'environment\t%s\n' $env
    end

    # ui_mode: emit only when a GUI backend is selected, so toggling it (or its
    # derived mounts/env) registers as drift and offers a restart.
    set -l ui_mode (_sandbox_config_read_ui_mode $p)
    if test "$ui_mode" != none
        printf 'ui_mode\t%s\n' $ui_mode
    end

    # network: emit when set so joining/leaving a network triggers drift detection.
    set -l network (_sandbox_config_read_network $p)
    if test -n "$network"
        printf 'network\t%s\n' $network
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

    # network: project overrides global (only one network at run time)
    set -l network (_sandbox_config_read_network $project_path)
    if test -n "$network"
        set args $args --network $network
    end

    # environment: global then project (docker-compose map or list form),
    # with variable expansion so values like ${HOME} resolve.
    for env in (yq -r --arg p $project_path \
        'def norm: if type=="object" then (to_entries|map("\(.key)=\(.value)")) elif type=="array" then . else [] end; ((.global.container.environment | norm) + (.projects[$p].container.environment | norm)) | .[]' $f 2>/dev/null)
        set args $args -e (_sandbox_expand_vars $env)
    end

    # ui_mode: wire up a display backend when configured. The entrypoint reads
    # SANDBOX_UI_MODE and installs any missing runtime libs on first start.
    set -l ui_mode (_sandbox_config_read_ui_mode $project_path)
    switch $ui_mode
        case none
            # no GUI plumbing
        case wslg
            if not uname -r | grep -qi microsoft
                echo "Error: ui_mode 'wslg' requires a WSL host (WSLg display server)." >&2
                echo "       Set 'ui_mode: none' for $project_path on this host." >&2
                return 1
            end
            set args $args -v /tmp/.X11-unix:/tmp/.X11-unix
            set args $args -v /mnt/wslg:/mnt/wslg
            set args $args -e DISPLAY=:0
            set args $args -e WAYLAND_DISPLAY=wayland-0
            set args $args -e XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir
            set args $args -e PULSE_SERVER=/mnt/wslg/PulseServer
            set args $args -e SANDBOX_UI_MODE=wslg
        case '*'
            echo "Error: unknown ui_mode '$ui_mode' for $project_path (valid: none, wslg)." >&2
            return 1
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
            echo ""
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

    # --- leading project/global selector flags (must precede the subcommand) ---
    set -l target_path $PROJECT_PATH
    set -l global_mode 0
    set -l project_flag 0
    set -l _subcmds stop list open restart git-auth mounts ui network
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
        printf "  %-34s%s\n" "restart <target>"      "Recreate a sandbox with current config and reattach"
        printf "  %-34s%s\n" "git-auth <action>"     "Manage per-project git auth"
        printf "  %-34s%s\n" "mounts <action>"       "Manage current project's volume entries"
        printf "  %-34s%s\n" "-g mounts <action>"    "Manage always-on global volume entries"
        printf "  %-34s%s\n" "ui [<mode>]"           "Show/set GUI display backend (none|wslg)"
        printf "  %-34s%s\n" "network [<name>|--clear]" "Show/set Docker network for this project"
        echo ""
        echo "Global flags (before the subcommand):"
        printf "  %-34s%s\n" "-p, --project <id|path>" "Target another project (path, container hash, or name)"
        printf "  %-34s%s\n" ""                        "Applies to: mounts, git-auth, open, restart, stop, ui"
        printf "  %-34s%s\n" "-g, --global"            "Operate on global config (mounts only)"
        echo ""
        echo "Run 'claude-sandbox <subcommand> --help' for subcommand usage."
        return 0
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
        set -l container_name (_sandbox_container_name $target_path)
        if not docker inspect $container_name > /dev/null 2>&1
            echo "No container found for $target_path"
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
                _sandbox_git_auth_wizard $target_path $target_name
            case show
                set -l t (_sandbox_config_read_git_auth_type $target_path)
                if test -z "$t"
                    echo "No git auth configured for $target_path"
                else
                    echo "type: $t"
                    if test "$t" = ssh; or test "$t" = pat
                        echo "path: "(_sandbox_config_read_git_auth_path $target_path)
                    end
                    if test "$t" = ssh
                        echo "prefer_ssh: "(_sandbox_config_read_git_auth_prefer_ssh $target_path)
                    end
                    set -l n (_sandbox_config_read_git_auth_identity_name $target_path)
                    set -l e (_sandbox_config_read_git_auth_identity_email $target_path)
                    if test -n "$n"; or test -n "$e"
                        echo "identity:"
                        echo "  name: $n"
                        echo "  email: $e"
                    end
                end
            case clear
                _sandbox_config_delete $target_path
                echo "Cleared git auth for $target_path (will prompt on next launch)"
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
        end
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
        return
    end

    # --- ui subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = ui
        if contains -- --help $argv
            echo "Usage: claude-sandbox [-p <project>] ui [<mode>]"
            echo ""
            echo "  Show or set the GUI display backend for a project."
            echo ""
            printf "  %-12s%s\n" "(no mode)" "Print the current ui_mode"
            printf "  %-12s%s\n" "none"      "Disable GUI plumbing (default)"
            printf "  %-12s%s\n" "wslg"      "WSLg sockets + display env + auto lib install (WSL only)"
            echo ""
            echo "  Apply changes to an existing container with 'claude-sandbox restart'."
            return 0
        end
        if test (count $argv) -lt 2
            echo "ui_mode: "(_sandbox_config_read_ui_mode $target_path)
            return
        end
        switch $argv[2]
            case none wslg
                _sandbox_config_write_ui_mode $target_path $argv[2]
                echo "Set ui_mode for $target_path: $argv[2]"
                if test "$argv[2]" != none
                    echo "Run 'claude-sandbox restart' to apply."
                end
            case '*'
                echo "Error: invalid ui_mode '$argv[2]' (valid: none, wslg)."
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
        if test $project_flag -eq 1
            _sandbox_launch $target_path
            return
        end
        if test (count $argv) -lt 2
            echo "Usage: claude-sandbox open <target>"
            return 1
        end
        set -l target $argv[2]
        set -l resolved (_sandbox_resolve_target $target)
        if test -z "$resolved"
            echo "Error: '$target' is neither an existing sandbox container nor a valid path."
            return 1
        end
        _sandbox_launch $resolved
        return
    end

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
            echo "    - A container name (e.g. claude-sandbox-abc12345) or its"
            echo "      bare hash (abc12345) from 'claude-sandbox list'."
            echo ""
            echo "  Any existing container for the target is stopped and removed first;"
            echo "  this ends any running Claude session in that container. If no"
            echo "  container exists for a path target, you are prompted before one"
            echo "  is created."
            return 0
        end
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

        set -l project_name (basename $resolved)
        set -l container_name (_sandbox_container_name $resolved)

        set -l rs_status (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)
        if test -n "$rs_status"
            # Existing container: show what will change (for transparency), then recreate.
            _sandbox_preflight $resolved; or return 1
            set -l drift_lines (_sandbox_config_diff $resolved $container_name)
            if test (count $drift_lines) -gt 0
                echo "Applying configuration changes to $project_name:"
                printf '%s\n' $drift_lines
            end
            echo "Restarting sandbox for $project_name..."
        else
            # No container yet: confirm before creating (default No). Run preflight
            # (which may launch the git-auth wizard) only after the user confirms, so
            # declining never writes auth config for a project we don't create.
            read -P "No sandbox exists for $resolved. Create one? [y/N] " answer
            or set answer n
            if not string match -qi 'y*' -- $answer
                echo "Aborted."
                return 1
            end
            _sandbox_preflight $resolved; or return 1
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

    # --- network subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = network
        if contains -- --help $argv
            echo "Usage: claude-sandbox [-p <project>] network [<name>|--clear]"
            echo ""
            echo "  Show or set the Docker network for a project."
            echo ""
            printf "  %-14s%s\n" "(no args)" "Print the current network"
            printf "  %-14s%s\n" "<name>"    "Join the named Docker network on next start"
            printf "  %-14s%s\n" "--clear"   "Remove network override (use default bridge)"
            echo ""
            echo "  The network must already exist: docker network create <name>"
            echo "  Apply changes to an existing container with 'claude-sandbox restart'."
            return 0
        end
        if test (count $argv) -lt 2
            set -l net (_sandbox_config_read_network $target_path)
            if test -n "$net"
                echo "network: $net"
            else
                echo "network: (default bridge)"
            end
            return
        end
        if test "$argv[2]" = --clear
            _sandbox_config_clear_network $target_path
            echo "Cleared network for $target_path (will use default bridge)"
        else
            _sandbox_config_write_network $target_path $argv[2]
            echo "Set network for $target_path: $argv[2]"
            echo "Run 'claude-sandbox restart' to apply."
        end
        return
    end

    # --- launch flow ---
    _sandbox_launch $target_path
end
