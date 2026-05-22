#!/bin/bash
set -euo pipefail

if [ "${SANDBOX_GIT_AUTH_TYPE:-}" = ssh ] && [ -f /home/claude/.gitcreds ]; then
    cat > /home/claude/.ssh/config << 'EOF'
Host *
  IdentityFile /home/claude/.gitcreds
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
    chmod 600 /home/claude/.ssh/config
fi

if [ "${SANDBOX_GIT_AUTH_TYPE:-}" = pat ] && [ -f /home/claude/.gitcreds ]; then
    TOKEN=$(cat /home/claude/.gitcreds)
    printf 'https://%s@github.com\n' "$TOKEN" > /home/claude/.git-credentials
    chmod 600 /home/claude/.git-credentials
    git config --global credential.helper "store --file /home/claude/.git-credentials"
fi

if [ -n "${SANDBOX_GIT_NAME:-}" ]; then
    git config --global user.name "$SANDBOX_GIT_NAME"
fi
if [ -n "${SANDBOX_GIT_EMAIL:-}" ]; then
    git config --global user.email "$SANDBOX_GIT_EMAIL"
fi
if [ "${SANDBOX_GIT_PREFER_SSH:-}" = 1 ]; then
    git config --global url."git@github.com:".insteadOf "https://github.com/"
fi

[ -f /home/claude/.claude/.claude.json ] || echo '{}' > /home/claude/.claude/.claude.json
ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json
exec "$@"
