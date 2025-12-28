#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"

# Target repository for release assets (keep in sync with generate_and_deploy_appcast.sh)
PUBLIC_REPO="${PUBLIC_REPO:-$GITHUB_REPOSITORY}"

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

gh release create "${VERSION}" \
  "build_output/BrainOS-${VERSION}.dmg" \
  "build_output/BrainOS.dmg" \
  "updates/arm64/BrainOS-${VERSION}.html" \
  --repo "${PUBLIC_REPO}" \
  --title "BrainOS ${VERSION}" \
  --notes-file RELEASE_NOTES.md \
  --latest

echo "✅ Release created successfully"
echo "📥 Latest download URL: https://github.com/${PUBLIC_REPO}/releases/latest/download/BrainOS.dmg"


