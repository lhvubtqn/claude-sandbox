#!/bin/bash
set -euo pipefail
if [ -s /home/claude/.ssh/repo_key ]; then
    chmod 600 /home/claude/.ssh/repo_key 2>/dev/null || true
    cat > /home/claude/.ssh/config << 'EOF'
Host *
  IdentityFile /home/claude/.ssh/repo_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
    chmod 600 /home/claude/.ssh/config
fi
exec "$@"
