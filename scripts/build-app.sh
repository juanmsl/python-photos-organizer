#!/usr/bin/env bash
# Builds a release "Photos Organizer.app" into dist/.
#
#   scripts/build-app.sh
#
# Environment:
#   SIGN_IDENTITY  codesign identity, e.g. "Developer ID Application: Name (TEAMID)".
#                  Defaults to "-" (ad-hoc signature: runs on this Mac; other Macs need right-click → Open).
#   UNIVERSAL=1    also build for Intel (needs Xcode; Command Line Tools only build for the host arch).
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP_NAME="Photos Organizer"
APP="dist/${APP_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

arch_flags=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  arch_flags=(--arch arm64 --arch x86_64)
fi

echo "==> Building PhotosOrganizer ${VERSION} (${BUILD}) in release mode"
swift build -c release --product PhotosOrganizer ${arch_flags[@]+"${arch_flags[@]}"}
BIN_DIR="$(swift build -c release --product PhotosOrganizer ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PhotosOrganizer" "$APP/Contents/MacOS/PhotosOrganizer"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD}/" packaging/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing with identity: ${SIGN_IDENTITY}"
sign_args=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  sign_args+=(--options runtime --timestamp)  # hardened runtime, required for notarization
fi
codesign "${sign_args[@]}" "$APP"
codesign --verify --strict "$APP"

echo "==> Done: $APP"
