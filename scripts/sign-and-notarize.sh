#!/usr/bin/env bash
# Sign GitEdit.app with the Developer ID Application identity, package it
# into a .dmg, submit to Apple notarization, and staple the ticket.
#
# Env:
#   SIGNING_IDENTITY      e.g. "Developer ID Application: Soware Tokyo Inc. (TEAMID)"
#   APPLE_ID              Apple ID email
#   APPLE_ID_PASSWORD     app-specific password (https://appleid.apple.com)
#   APPLE_TEAM_ID         10-char team ID
#   APP_VERSION           default 0.1.0
set -euo pipefail

APP_NAME="GitEdit"
VERSION="${APP_VERSION:-0.1.0}"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
STAGING="${BUILD_DIR}/dmg-staging"

if [[ ! -d "${APP_DIR}" ]]; then
    echo "❌ ${APP_DIR} not found — run scripts/build-app.sh first" >&2
    exit 1
fi
: "${SIGNING_IDENTITY:?SIGNING_IDENTITY must be set}"
: "${APPLE_ID:?APPLE_ID must be set}"
: "${APPLE_ID_PASSWORD:?APPLE_ID_PASSWORD must be set}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID must be set}"

echo "==> Codesigning ${APP_DIR}"
# Sign nested executables/frameworks first, then the outer bundle.
find "${APP_DIR}/Contents" \( -name "*.dylib" -o -name "*.framework" \) -print0 \
    | while IFS= read -r -d '' nested; do
        codesign --force --options runtime --timestamp \
            --sign "${SIGNING_IDENTITY}" "${nested}"
    done

codesign --force --options runtime --timestamp \
    --entitlements scripts/entitlements.plist \
    --sign "${SIGNING_IDENTITY}" \
    "${APP_DIR}"

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "==> Building DMG ${DMG_PATH}"
rm -rf "${STAGING}" "${DMG_PATH}"
mkdir -p "${STAGING}"
cp -R "${APP_DIR}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}"
rm -rf "${STAGING}"

codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "${DMG_PATH}"

echo "==> Submitting to Apple notary service (this can take a few minutes)"
xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID}" \
    --password "${APPLE_ID_PASSWORD}" \
    --team-id "${APPLE_TEAM_ID}" \
    --wait

echo "==> Stapling ticket"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

echo "✅ Notarized: ${DMG_PATH}"
