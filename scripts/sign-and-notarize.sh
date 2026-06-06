#!/usr/bin/env bash
# Sign GitEdit.app with the Developer ID Application identity, package it
# into a .dmg with a polished layout, submit to Apple notarization, and
# staple the ticket.
#
# Env:
#   SIGNING_IDENTITY      e.g. "Developer ID Application: Soware Tokyo Inc. (TEAMID)"
#   APPLE_ID              Apple ID email
#   APPLE_ID_PASSWORD     app-specific password (https://appleid.apple.com)
#   APPLE_TEAM_ID         10-char team ID
#   APP_VERSION           default 0.1.0 (used for the DMG volume label only —
#                         the output file is always GitEdit.dmg so the URL
#                         "releases/latest/download/GitEdit.dmg" stays stable)
set -euo pipefail

APP_NAME="GitEdit"
VERSION="${APP_VERSION:-0.1.0}"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
# Stable filename so the latest-release URL never changes between versions.
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
VOLNAME="${APP_NAME} ${VERSION}"
BACKGROUND="scripts/assets/dmg-background.png"

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

echo "==> Ensuring create-dmg is available"
if ! command -v create-dmg >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        brew install create-dmg
    else
        echo "❌ create-dmg not found. Install via: brew install create-dmg" >&2
        exit 1
    fi
fi

echo "==> Building DMG ${DMG_PATH}"
rm -f "${DMG_PATH}"

# Optional custom background. Looks for scripts/assets/dmg-background.png
# (540x380, designed for the 540x380 window layout below).
DMG_ARGS=(
    --volname "${VOLNAME}"
    --volicon "${APP_DIR}/Contents/Resources/AppIcon.icns"
    --window-pos 200 120
    --window-size 540 380
    --icon-size 96
    --icon "${APP_NAME}.app" 140 200
    --hide-extension "${APP_NAME}.app"
    --app-drop-link 400 200
    --no-internet-enable
)
if [[ -f "${BACKGROUND}" ]]; then
    DMG_ARGS+=(--background "${BACKGROUND}")
    echo "    (using custom background ${BACKGROUND})"
fi

create-dmg "${DMG_ARGS[@]}" "${DMG_PATH}" "${APP_DIR}"

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
