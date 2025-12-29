#!/bin/bash
# Patch MLX-swift-lm to fix Message type ambiguity
# This script patches the MLXVLM files to use fully-qualified MLXLMCommon.Message type

set -e

CHECKOUT_DIR="Packages/BrainCore/.build/checkouts/mlx-swift-lm"
MODELS_DIR="$CHECKOUT_DIR/Libraries/MLXVLM/Models"

if [ ! -d "$CHECKOUT_DIR" ]; then
    echo "⚠️  MLX checkout not found at $CHECKOUT_DIR"
    echo "   Run 'swift package resolve' first in Packages/BrainCore/"
    exit 0
fi

echo "🔧 Patching MLX-swift-lm for Message type ambiguity..."

# Make writable
chmod -R u+w "$CHECKOUT_DIR" 2>/dev/null || true

# Files to patch
FILES=(
    "$MODELS_DIR/FastVLM.swift"
    "$MODELS_DIR/Qwen2VL.swift"
    "$MODELS_DIR/Qwen3VL.swift"
    "$MODELS_DIR/SmolVLM2.swift"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        # Fix return types: -> Message { -> -> MLXLMCommon.Message {
        sed -i '' 's/-> Message {/-> MLXLMCommon.Message {/g' "$file"
        # Fix return array types: -> [Message] { -> -> [MLXLMCommon.Message] {
        sed -i '' 's/-> \[Message\] {/-> [MLXLMCommon.Message] {/g' "$file"
        # Fix parameter types: _ messages: [Message] -> _ messages: [MLXLMCommon.Message]
        sed -i '' 's/_ messages: \[Message\]/_ messages: [MLXLMCommon.Message]/g' "$file"
        echo "   ✓ Patched $(basename "$file")"
    fi
done

echo "✅ MLX patch complete!"
