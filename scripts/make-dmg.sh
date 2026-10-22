#!/usr/bin/env bash
# Builds the app and packages it as dist/PhotosOrganizer-<version>.dmg, with an Applications
# shortcut so users can drag the app to install it.
#
#   scripts/make-dmg.sh
#
# Environment (all optional):
#   SIGN_IDENTITY   see build-app.sh; the DMG is signed with it too when it is not ad-hoc.
#   NOTARY_PROFILE  a `xcrun notarytool store-credentials` profile; when set, the DMG is notarized
#                   and stapled so it opens on any Mac without Gatekeeper warnings.
set -euo pipefail

cd "$(dirname "$0")/.."
scripts/build-app.sh

VERSION="$(tr -d '[:space:]' < VERSION)"
APP_NAME="Photos Organizer"
DMG="dist/PhotosOrganizer-${VERSION}.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "dist/${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating ${DMG}"
rm -f "$DMG"
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarizing (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

hdiutil verify "$DMG" >/dev/null
echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
