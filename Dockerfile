FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System deps (from official Solana docs for Ubuntu/Debian)
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libudev-dev \
    llvm \
    libclang-dev \
    protobuf-compiler \
    libssl-dev \
    curl \
    git \
    ca-certificates \
    python3 \
    python3-pip \
    sudo \
    && rm -rf /var/lib/apt/lists/*

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
RUN mkdir -p /home/claude/.vscode-server

# Rust, Solana CLI, Anchor, Node.js, Yarn — official all-in-one install
RUN curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash

# Bake all tool paths into every process (login shell not required)
ENV NVM_DIR=/home/claude/.nvm
ENV PATH="/home/claude/.cargo/bin:/home/claude/.local/share/solana/install/active_release/bin:/home/claude/.avm/bin:/home/claude/.local/bin:/home/claude/.nvm/default-node-bin:${PATH}"

# Create a stable /home/claude/.nvm/default-node-bin symlink that points to
# whichever node version NVM just installed as default. No root needed.
RUN bash -c "source $NVM_DIR/nvm.sh && \
    nvm alias default node && \
    ln -sf \$(dirname \$(nvm which default)) $NVM_DIR/default-node-bin"

# Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

COPY --chown=claude:claude entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /workspace
