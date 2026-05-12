function _sandbox_creds_file
    echo $HOME/.claude-sandbox/project-creds.json
end

function _sandbox_creds_read_type
    # Returns "ssh", "none", or empty string if no entry exists
    set -l f (_sandbox_creds_file)
    test -f $f; or begin; echo ""; return; end
    jq -r --arg p $argv[1] '.[$p].type // empty' $f
end

function _sandbox_creds_read_key
    # Returns keyPath or empty string
    set -l f (_sandbox_creds_file)
    test -f $f; or begin; echo ""; return; end
    jq -r --arg p $argv[1] '.[$p].keyPath // empty' $f
end

function _sandbox_creds_write_ssh
    # Usage: _sandbox_creds_write_ssh <project_path> <key_path>
    set -l f (_sandbox_creds_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    jq --arg p $argv[1] --arg k $argv[2] \
        '.[$p] = {"type": "ssh", "keyPath": $k}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_creds_write_none
    # Usage: _sandbox_creds_write_none <project_path>
    set -l f (_sandbox_creds_file)
    test -f $f; or echo '{}' > $f
    set -l tmp (mktemp)
    jq --arg p $argv[1] '.[$p] = {"type": "none"}' $f > $tmp
    and mv $tmp $f
end

function _sandbox_creds_delete
    # Usage: _sandbox_creds_delete <project_path>
    set -l f (_sandbox_creds_file)
    test -f $f; or return
    set -l tmp (mktemp)
    jq --arg p $argv[1] 'del(.[$p])' $f > $tmp
    and mv $tmp $f
end

function _sandbox_expand_path
    # Expand leading ~ to $HOME in a path read from user input
    string replace -r '^~/' $HOME/ $argv[1]
end

function _sandbox_copy_pubkey
    # Usage: _sandbox_copy_pubkey <pubkey_file_path>
    # Copies content to clipboard on WSL2; falls back to printing content
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
    # Runs the interactive credential setup wizard.
    # On success, writes entry to project-creds.json and returns 0.
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
                set key_path (_sandbox_expand_path $key_path)
            end

            ssh-keygen -t ed25519 -f $key_path -C "$project_name deploy key" -N ""
            or return 1

            echo ""
            echo "Key generated at $key_path"
            _sandbox_copy_pubkey "$key_path.pub"
            echo ""
            echo "GitHub : repo Settings → Deploy keys → Add deploy key  (enable \"Allow write access\" if needed)"
            echo "GitLab : repo Settings → Repository → Deploy keys"
            echo ""
            read -P "Press Enter when done to launch the sandbox..." _dummy

            _sandbox_creds_write_ssh $project_path $key_path

        case 2
            read -P "SSH key path: " key_path
            set key_path (_sandbox_expand_path $key_path)
            if not test -f $key_path
                echo "Error: key file not found: $key_path"
                return 1
            end
            _sandbox_creds_write_ssh $project_path $key_path

        case 3
            _sandbox_creds_write_none $project_path

        case '*'
            echo "Error: invalid choice '$choice'"
            return 1
    end
end

function claude-sandbox
    set PROJECT_PATH (pwd)
    set PROJECT_NAME (basename $PROJECT_PATH)
    set SANDBOX_DIR $HOME/.claude-sandbox

    if not docker info > /dev/null 2>&1
        echo "Error: Docker is not running. Please start Docker Desktop first."
        return 1
    end

    set -x PROJECT_PATH $PROJECT_PATH
    set -x PROJECT_NAME $PROJECT_NAME

    echo "Starting sandbox for $PROJECT_NAME..."

    if not docker compose -f $SANDBOX_DIR/docker-compose.yml up -d --force-recreate
        echo "Error: Failed to start the sandbox container."
        return 1
    end

    set container_json "{\"containerName\":\"/claude-sandbox\"}"
    set encoded (printf '%s' $container_json | xxd -p | tr -d '\n')

    code --folder-uri "vscode-remote://attached-container+$encoded/workspace/$PROJECT_NAME"
end
