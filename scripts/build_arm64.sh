#!/usr/bin/env bash
set -euo pipefail

# Backward-compat: if DEVELOPMENT_TEAM not set, fall back to APPLE_TEAM_ID
if [[ -z "${DEVELOPMENT_TEAM:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  export DEVELOPMENT_TEAM="${APPLE_TEAM_ID}"
fi

: "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM is required}"
: "${DEVELOPER_ID_NAME:?DEVELOPER_ID_NAME is required}"
: "${VERSION:?VERSION is required}"

echo "Building ARM64 version (default)..."

# Normalize identity: allow DEVELOPER_ID_NAME with or without the product prefix
CODE_SIGN_IDENTITY_VALUE="${DEVELOPER_ID_NAME}"
if [[ "${CODE_SIGN_IDENTITY_VALUE}" != Developer\ ID\ Application:* ]]; then
  CODE_SIGN_IDENTITY_VALUE="Developer ID Application: ${CODE_SIGN_IDENTITY_VALUE}"
fi

# Ensure a clean and consistent SPM resolution before archiving
rm -f "Packages/BrainOSCore/Package.resolved"
rm -rf build/DerivedData build/SourcePackages
xcodebuild -resolvePackageDependencies -project App/BrainOS.xcodeproj -scheme BrainOS

# 1. Build the CLI first (as a separate scheme)
echo "Building CLI (BrainOSCLI)..."
xcodebuild -project App/BrainOS.xcodeproj \
  -scheme BrainOS-cli \
  -configuration Release \
  -derivedDataPath build \
  ARCHS=arm64 \
  VALID_ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY_VALUE}" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
  CODE_SIGN_STYLE=Manual \
  clean build

# 2. Archive the App (which doesn't have the CLI embedded yet via Xcode)
echo "Archiving App (BrainOS)..."
xcodebuild -project App/BrainOS.xcodeproj \
  -scheme BrainOS \
  -configuration Release \
  -derivedDataPath build \
  ARCHS=arm64 \
  VALID_ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${VERSION}" \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY_VALUE}" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
  CODE_SIGN_STYLE=Manual \
  archive -archivePath build/BrainOS.xcarchive

# 3. Manually Embed the CLI into the Archive
echo "Embedding CLI into Archive (Helpers)..."
CLI_SRC="build/Build/Products/Release/BrainOS-cli"
ARCHIVE_APP="build/BrainOS.xcarchive/Products/Applications/BrainOS.app"

if [[ ! -f "$CLI_SRC" ]]; then
  echo "Error: CLI binary not found at $CLI_SRC"
  exit 1
fi

# Copy to Helpers folder as 'BrainOS'
mkdir -p "$ARCHIVE_APP/Contents/Helpers"
cp "$CLI_SRC" "$ARCHIVE_APP/Contents/Helpers/BrainOS"
chmod +x "$ARCHIVE_APP/Contents/Helpers/BrainOS"

# Re-sign the modified app bundle inside the archive
# (Use --deep to sign the nested CLI binary as well, but explicitly re-apply entitlements)
echo "Re-signing modified app bundle..."
codesign --force --deep --options runtime --entitlements "App/BrainOS/BrainOS.entitlements" --sign "${CODE_SIGN_IDENTITY_VALUE}" "$ARCHIVE_APP"

cat > ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath build/BrainOS.xcarchive \
  -exportPath build_output \
  -exportOptionsPlist ExportOptions.plist
