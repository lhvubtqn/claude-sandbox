#!/bin/bash
set -euo pipefail
if [ -s /home/claude/.ssh/deploy_key ]; then
    cat > /home/claude/.ssh/config << 'EOF'
Host *
  IdentityFile /home/claude/.ssh/deploy_key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
    chmod 600 /home/claude/.ssh/config
fi
[ -f /home/claude/.claude/.claude.json ] || echo '{}' > /home/claude/.claude/.claude.json
ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json
exec "$@"
