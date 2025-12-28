#!/bin/bash

# setup_exo.sh - Helper script to set up exo for multi-device distributed inference

echo "🚀 Setting up exo for BrainOS..."

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "📦 Installing uv (fast Python package manager)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source $HOME/.cargo/env
fi

# Clone exo if not already present
if [ ! -d "ThirdParty/exo" ]; then
    echo "📂 Cloning exo repository..."
    mkdir -p ThirdParty
    git clone https://github.com/exo-explore/exo.git ThirdParty/exo
fi

cd ThirdParty/exo

# Install dependencies
echo "🛠️ Installing exo dependencies..."
uv sync

echo "✅ exo is ready!"
echo "To start exo, run: cd ThirdParty/exo && uv run exo"
