FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System deps needed before the Solana installer runs (it needs curl to fetch
# itself and sudo for its own apt installs). We install libclang1-18 here — the
# libclang runtime shared library that bindgen dlopens (clang-sys locates it
# without llvm-config or the dev headers). Installing it here marks it `manual`
# so it survives the cleanup in the Solana layer below: that installer pulls in
# the full llvm/libclang-dev dev stack (~840MB), which we purge afterward,
# keeping only libclang1-18 + libllvm18 — verified bindgen and `anchor build`
# both work with libclang1-18 alone.
# Package docs/manpages are stripped in the same layer to keep the image lean.
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libudev-dev \
    libclang1-18 \
    protobuf-compiler \
    libssl-dev \
    curl \
    git \
    ca-certificates \
    python3 \
    python3-pip \
    pipx \
    sudo \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*

# Create non-root user (claude --dangerously-skip-permissions requires non-root)
# Ubuntu 24.04 ships with a user 'ubuntu' at UID 1000; rename it to 'claude'
RUN usermod -l claude -d /home/claude -m ubuntu && \
    groupmod -n claude ubuntu && \
    echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
RUN mkdir -p /workspace && chown claude:claude /workspace

USER claude
ENV HOME=/home/claude

# Pre-create dirs that are backed by named volumes — Docker initializes a named
# volume from the image only if the volume is empty, so ownership must be set here.
RUN mkdir -p /home/claude/.vscode-server /home/claude/.ssh /home/claude/.npm-globals /home/claude/.pipx && \
    chmod 700 /home/claude/.ssh

# Rust, Solana CLI, Anchor, Node.js, Yarn — official all-in-one install.
# The installer runs its own `apt-get install ... llvm libclang-dev ...`, which
# re-adds the full ~840MB LLVM dev stack. Purge it here in the SAME layer (the
# install has already finished, so nothing downstream needs it), keeping only
# libclang1-18 + libllvm18 for bindgen. Also strip the bundled Rust offline HTML
# docs (~800MB) in this layer — a later RUN couldn't reclaim space already
# committed to this one.
RUN curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash \
    && sudo apt-get purge -y \
        llvm llvm-runtime llvm-18 llvm-18-dev llvm-18-tools llvm-18-runtime \
        llvm-18-linker-tools libclang-dev libclang-18-dev libclang-common-18-dev \
        libclang-cpp18 libclang-rt-18-dev \
    && sudo apt-get autoremove --purge -y \
    && sudo rm -rf /var/lib/apt/lists/* \
    && rm -rf /home/claude/.rustup/toolchains/*/share/doc \
              /home/claude/.rustup/toolchains/*/share/man

# The Solana installer added raw nvm init to ~/.bashrc. Patch it to temporarily
# unset NPM_CONFIG_PREFIX (which nvm.sh rejects) and restore it after loading.
RUN python3 - << 'EOF'
import re
path = '/home/claude/.bashrc'
with open(path) as f:
    text = f.read()
text = re.sub(
    r'(\[ -s "\$NVM_DIR/nvm\.sh" \] && \\?\. "\$NVM_DIR/nvm\.sh")(.*)',
    '_p="${NPM_CONFIG_PREFIX:-}"; unset NPM_CONFIG_PREFIX; \\1\\2; [ -n "$_p" ] && export NPM_CONFIG_PREFIX="$_p"; unset _p',
    text
)
with open(path, 'w') as f:
    f.write(text)
EOF

# Bake all tool paths into every process (login shell not required)
ENV NVM_DIR=/home/claude/.nvm
ENV NPM_CONFIG_PREFIX=/home/claude/.npm-globals
# pipx home and bin dir both live under the cached pipx volume so installed apps
# (venvs) and their app symlinks persist together across restarts/rebuilds.
ENV PIPX_HOME=/home/claude/.pipx
ENV PIPX_BIN_DIR=/home/claude/.pipx/bin
ENV PIPX_MAN_DIR=/home/claude/.pipx/man
ENV PATH="/home/claude/.cargo/bin:/home/claude/.local/share/solana/install/active_release/bin:/home/claude/.avm/bin:/home/claude/.local/bin:/home/claude/.npm-globals/bin:/home/claude/.pipx/bin:/home/claude/.nvm/default-node-bin:${PATH}"

# Create a stable /home/claude/.nvm/default-node-bin symlink that points to
# whichever node version NVM just installed as default. No root needed.
RUN bash -c "unset NPM_CONFIG_PREFIX; source $NVM_DIR/nvm.sh && \
    nvm alias default node && \
    ln -sf \$(dirname \$(nvm which default)) $NVM_DIR/default-node-bin"

# Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

RUN printf '#!/bin/sh\nexec claude --dangerously-skip-permissions "$@"\n' \
    > /home/claude/.local/bin/yolo && chmod +x /home/claude/.local/bin/yolo

COPY --chown=claude:claude entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /workspace
