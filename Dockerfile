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
    && rm -rf /var/lib/apt/lists/*

# Rust, Solana CLI, Anchor, Node.js, Yarn — official all-in-one install
RUN curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash

# Bake all tool paths into every process (login shell not required)
ENV NVM_DIR=/root/.nvm
ENV PATH="/root/.cargo/bin:/root/.local/share/solana/install/active_release/bin:/root/.avm/bin:/root/.local/bin:${PATH}"

# Set NVM default version and symlink to /usr/local/bin so they're available in all shells
RUN bash -c "source $NVM_DIR/nvm.sh && \
    nvm alias default node && \
    node_bin=\$(dirname \$(nvm which default)) && \
    for bin in node npm npx yarn; do \
        ln -sf \$node_bin/\$bin /usr/local/bin/\$bin 2>/dev/null || true; \
    done"

# Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Git config
COPY gitconfig /root/.gitconfig

WORKDIR /workspace
