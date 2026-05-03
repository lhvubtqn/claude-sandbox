FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# System deps
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    pkg-config \
    libssl-dev \
    libudev-dev \
    python3 \
    python3-pip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Rust (stable)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
ENV PATH="/root/.cargo/bin:${PATH}"

# Solana CLI (stable)
RUN sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

# AVM + Anchor (latest stable at build time)
RUN cargo install avm \
    && avm install latest \
    && avm use latest

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Git config
COPY gitconfig /root/.gitconfig

WORKDIR /workspace
