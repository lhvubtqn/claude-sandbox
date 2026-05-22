function _sandbox_config_file
    echo $HOME/.claude-sandbox/configurations.yml
end

function _sandbox_config_read_creds_type
    # Returns "ssh", "none", or empty string if no entry exists
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].credentials.type // empty' $f 2>/dev/null
end

function _sandbox_config_read_creds_key
    # Returns keyPath or empty string
    set -l f (_sandbox_config_file)
    test -f $f; or begin; echo ""; return; end
    yq -r --arg p $argv[1] '.projects[$p].credentials.keyPath // empty' $f 2>/dev/null
end

function _sandbox_config_write_creds_ssh
    # Usage: _sandbox_config_write_creds_ssh <project_path> <key_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg k $argv[2] \
        '.projects[$p].credentials = {"type": "ssh", "keyPath": $k}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_write_creds_none
    # Usage: _sandbox_config_write_creds_none <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] \
        '.projects[$p].credentials = {"type": "none"}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_config_delete
    # Usage: _sandbox_config_delete <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] 'del(.projects[$p].credentials)' $f > $tmp
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

    # SSH deploy key (credentials-managed, not in volumes list)
    set -l creds_type (_sandbox_config_read_creds_type $project_path)
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_expand_vars (_sandbox_config_read_creds_key $project_path))
        set args $args -v "$key_path:/home/claude/.ssh/deploy_key:ro"
    end

    # Project workspace bind mount
    set args $args -v "$project_path:/workspace/$project_name"

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


function _sandbox_creds_wizard
    # Usage: _sandbox_creds_wizard <project_path> <project_name>
    set -l project_path $argv[1]
    set -l project_name $argv[2]

    echo ""
    echo "No SSH credentials configured for \"$project_path\"."
    echo ""
    echo "  1. Generate a new deploy key"
    echo "  2. Use an existing key"
    echo "  3. Skip (no git credentials)"
    echo ""
    read -P "Choice: " choice

    switch $choice
        case 1
            set -l default_path $HOME/.ssh/id_ed25519_$project_name
            read -P "Key path [$default_path]: " key_path
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

            _sandbox_config_write_creds_ssh $project_path $key_path

        case 2
            read -P "SSH key path: " key_path
            set key_path (_sandbox_expand_vars $key_path)
            if not test -f $key_path
                echo "Error: key file not found: $key_path"
                return 1
            end
            _sandbox_config_write_creds_ssh $project_path $key_path

        case 3
            _sandbox_config_write_creds_none $project_path

        case '*'
            echo "Error: invalid choice '$choice'"
            return 1
    end
end

function claude-sandbox
    set -l PROJECT_PATH (pwd)
    set -l PROJECT_NAME (basename $PROJECT_PATH)
    set -l SANDBOX_DIR $HOME/.claude-sandbox

    # --- global subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = global
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

    # --- creds subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = creds
        set -l action $argv[2]
        switch $action
            case set
                if test (count $argv) -ge 3
                    set -l key_path (_sandbox_expand_vars $argv[3])
                    if not test -f $key_path
                        echo "Error: key file not found: $key_path"
                        return 1
                    end
                    _sandbox_config_write_creds_ssh $PROJECT_PATH $key_path
                    echo "Saved SSH key for $PROJECT_PATH"
                else
                    _sandbox_creds_wizard $PROJECT_PATH $PROJECT_NAME
                end
            case show
                set -l t (_sandbox_config_read_creds_type $PROJECT_PATH)
                if test -z "$t"
                    echo "No credentials configured for $PROJECT_PATH"
                else if test "$t" = ssh
                    echo "type: ssh"
                    echo "keyPath: "(_sandbox_config_read_creds_key $PROJECT_PATH)
                else
                    echo "type: none (no git credentials)"
                end
            case clear
                _sandbox_config_delete $PROJECT_PATH
                echo "Cleared credentials for $PROJECT_PATH (will prompt on next launch)"
            case list
                set -l f (_sandbox_config_file)
                if not test -f $f
                    echo "No credentials configured."
                    return
                end
                yq -r '(.projects // {}) | to_entries[] | select(.value.credentials != null) | "\(.key)\n  type: \(.value.credentials.type)" + (if .value.credentials.keyPath then "\n  keyPath: \(.value.credentials.keyPath)" else "" end)' $f
            case '*'
                echo "Usage: claude-sandbox creds {set [key-path]|show|clear|list}"
                return 1
        end
        return
    end

    # --- mounts subcommand ---
    if test (count $argv) -gt 0; and test $argv[1] = mounts
        set -l action $argv[2]
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

    # --- launch flow ---
    if not docker info > /dev/null 2>&1
        echo "Error: Docker is not running. Please start Docker Desktop first."
        return 1
    end

    # Resolve credentials for this project
    set -l creds_type (_sandbox_config_read_creds_type $PROJECT_PATH)
    if test -z "$creds_type"
        _sandbox_creds_wizard $PROJECT_PATH $PROJECT_NAME
        or return 1
        set creds_type (_sandbox_config_read_creds_type $PROJECT_PATH)
    end

    # Verify SSH key exists if configured
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_expand_vars (_sandbox_config_read_creds_key $PROJECT_PATH))
        if not test -f $key_path
            echo "Error: SSH key not found: $key_path"
            echo "Run 'claude-sandbox creds set' to reconfigure."
            return 1
        end
    end

    set -l container_name (_sandbox_container_name $PROJECT_PATH)
    set -l container_status (docker inspect --format '{{.State.Status}}' $container_name 2>/dev/null)

    switch $container_status
        case running
            echo "Attaching to running sandbox for $PROJECT_NAME..."
        case exited created paused
            echo "Starting sandbox for $PROJECT_NAME..."
            docker start $container_name
            or begin
                echo "Error: Failed to start container."
                return 1
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

    set -l container_json "{\"containerName\":\"/$container_name\"}"
    set -l encoded (printf '%s' $container_json | xxd -p | tr -d '\n')
    code --folder-uri "vscode-remote://attached-container+$encoded/workspace/$PROJECT_NAME"
end
