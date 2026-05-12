#!/bin/bash
if [ -s /home/claude/.ssh/repo_key ]; then
    mkdir -p /home/claude/.ssh
    sudo chown claude:claude /home/claude/.ssh
    chmod 700 /home/claude/.ssh
    cat > /home/claude/.ssh/config << 'EOF'
Host *
  IdentityFile /home/claude/.ssh/repo_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
    chmod 600 /home/claude/.ssh/config
fi
exec "$@"
