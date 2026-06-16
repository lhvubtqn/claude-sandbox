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
    printf 'https://x-access-token:%s@github.com\n' "$TOKEN" > /home/claude/.git-credentials
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

# GUI support: install the runtime libraries Godot/Electron/GTK/Qt apps need to
# reach the WSLg display. Only the packages actually missing are installed, so a
# warm container start is a fast no-op. The base image stays lean for non-GUI
# sandboxes (ui_mode: none, the default).
if [ "${SANDBOX_UI_MODE:-}" = wslg ]; then
    UI_PKGS="libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libxext6 \
libxrender1 libxfixes3 libxkbcommon0 libxkbcommon-x11-0 libgl1 libegl1 \
libgl1-mesa-dri libglu1-mesa libfontconfig1 libfreetype6 libdbus-1-3 \
libwayland-client0 libwayland-cursor0 libwayland-egl1 libdecor-0-0 \
libasound2t64 libpulse0"
    missing=""
    for p in $UI_PKGS; do
        dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
    done
    if [ -n "$missing" ]; then
        echo "[claude-sandbox] installing WSLg UI libraries:$missing"
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing
        sudo rm -rf /var/lib/apt/lists/*
    fi
fi

[ -f /home/claude/.claude/.claude.json ] || echo '{}' > /home/claude/.claude/.claude.json
ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json
exec "$@"
