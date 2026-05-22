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
    # Usage: _sandbox_mounts_list <project_path>
    # Prints each mount spec on its own line; prints nothing if no mounts configured
    set -l f (_sandbox_config_file)
    test -f $f; or return
    yq -r --arg p $argv[1] '.projects[$p].mounts // [] | .[]' $f 2>/dev/null
end

function _sandbox_mounts_add
    # Usage: _sandbox_mounts_add <project_path> <mount_spec>
    set -l f (_sandbox_config_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.projects[$p].mounts = ((.projects[$p].mounts // []) + [$m])' $f > $tmp
    and mv $tmp $f
end

function _sandbox_mounts_remove
    # Usage: _sandbox_mounts_remove <project_path> <mount_spec>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l count (yq -r --arg p $argv[1] '.projects[$p].mounts | length' $f 2>/dev/null)
    test "$count" -gt 0 2>/dev/null; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] --arg m $argv[2] \
        '.projects[$p].mounts = [(.projects[$p].mounts // [])[] | select(. != $m)]' $f > $tmp
    and mv $tmp $f
end

function _sandbox_mounts_clear
    # Usage: _sandbox_mounts_clear <project_path>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg p $argv[1] 'del(.projects[$p].mounts)' $f > $tmp
    and mv $tmp $f
end

function _sandbox_global_mounts_list
    set -l f (_sandbox_config_file)
    test -f $f; or return
    yq -r '.global.mounts // [] | .[]' $f 2>/dev/null
end

function _sandbox_global_mounts_add
    # Usage: _sandbox_global_mounts_add <mount_spec>
    set -l f (_sandbox_config_file)
    test -f $f; or echo 'global: {}' > $f
    set -l tmp (mktemp)
    yq -y --arg m $argv[1] \
        '.global.mounts = ((.global.mounts // []) + [$m])' $f > $tmp
    and mv $tmp $f
end

function _sandbox_global_mounts_remove
    # Usage: _sandbox_global_mounts_remove <mount_spec>
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y --arg m $argv[1] \
        '.global.mounts = [(.global.mounts // [])[] | select(. != $m)]' $f > $tmp
    and mv $tmp $f
end

function _sandbox_global_mounts_clear
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l tmp (mktemp)
    yq -y 'del(.global.mounts)' $f > $tmp
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

function _sandbox_migrate_from_json
    # Auto-migrate project-creds.json -> configurations.yml on first run after update
    set -l old_f $HOME/.claude-sandbox/project-creds.json
    set -l new_f (_sandbox_config_file)
    test -f $old_f; or return
    test -f $new_f; and return
    echo "Migrating project-creds.json to configurations.yml..."
    set -l tmp (mktemp)
    jq 'to_entries | map({key: .key, value: {credentials: .value}}) | from_entries' $old_f \
        | yq -y . > $tmp
    and mv $tmp $new_f
    and rm $old_f
    and echo "Migration complete."
end

function _sandbox_migrate_to_nested
    # Migrate flat schema (project paths as top-level keys) to global/projects schema.
    set -l f (_sandbox_config_file)
    test -f $f; or return
    set -l has_global (yq -r 'if .global != null then "yes" else "no" end' $f 2>/dev/null)
    set -l has_projects (yq -r 'if .projects != null then "yes" else "no" end' $f 2>/dev/null)
    if test "$has_global" = yes; or test "$has_projects" = yes
        return
    end
    echo "Migrating configurations.yml to global/projects schema..."
    set -l tmp (mktemp)
    yq -y '{global: {mounts: ["~/.claude-sandbox/.gitconfig:/home/claude/.gitconfig:ro", "~/.claude-sandbox/skills:/home/claude/.claude/skills:ro", "~/.claude-sandbox/rules:/home/claude/.claude/rules:ro"]}, projects: .}' \
        $f > $tmp
    and mv $tmp $f
    and echo "Migration complete."
end

function _sandbox_generate_override
    # Usage: _sandbox_generate_override <project_path> <project_name>
    set -l project_path $argv[1]
    set -l project_name $argv[2]
    set -l out $HOME/.claude-sandbox/docker-compose.override.yml

    set -l volumes \
        "      - $project_path:/workspace/$project_name"

    for m in (_sandbox_global_mounts_list)
        set volumes $volumes "      - "(_sandbox_expand_path $m)
    end

    set -l creds_type (_sandbox_config_read_creds_type $project_path)
    if test "$creds_type" = ssh
        set -l key_path (_sandbox_config_read_creds_key $project_path)
        set volumes $volumes "      - $key_path:/home/claude/.ssh/deploy_key:ro"
    end

    for m in (_sandbox_mounts_list $project_path)
        set volumes $volumes "      - $m"
    end

    printf 'services:\n  claude-sandbox:\n    working_dir: /workspace/%s\n    volumes:\n' \
        $project_name > $out
    for vol in $volumes
        printf '%s\n' $vol >> $out
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

    # Auto-migrate from legacy project-creds.json
    _sandbox_migrate_from_json
    # Migrate flat schema to global/projects schema
    _sandbox_migrate_to_nested

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
        set -l key_path (_sandbox_config_read_creds_key $PROJECT_PATH)
        if not test -f $key_path
            echo "Error: SSH key not found: $key_path"
            echo "Run 'claude-sandbox creds set' to reconfigure."
            return 1
        end
    end

    echo "Starting sandbox for $PROJECT_NAME..."

    # Generate docker-compose.override.yml for this project
    _sandbox_generate_override $PROJECT_PATH $PROJECT_NAME

    if not docker compose -f $SANDBOX_DIR/docker-compose.yml -f $SANDBOX_DIR/docker-compose.override.yml up -d --force-recreate
        echo "Error: Failed to start the sandbox container."
        return 1
    end

    set container_json "{\"containerName\":\"/claude-sandbox\"}"
    set encoded (printf '%s' $container_json | xxd -p | tr -d '\n')

    code --folder-uri "vscode-remote://attached-container+$encoded/workspace/$PROJECT_NAME"
end
