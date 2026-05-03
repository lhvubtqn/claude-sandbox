FROM ubuntu:22.04

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

# Use login shell so subsequent RUN steps pick up PATH from ~/.bashrc
SHELL ["/bin/bash", "-l", "-c"]

# Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Git config
COPY gitconfig /root/.gitconfig

WORKDIR /workspace
