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
