#!/usr/bin/env bash
# Build GitEdit.app (Universal: arm64 + x86_64) from the SwiftPM target.
# Outputs: build/GitEdit.app
#
# Env:
#   APP_VERSION      (default 0.1.0) — CFBundleShortVersionString
#   APP_BUILD        (default 1)     — CFBundleVersion
#   SPARKLE_FEED_URL (default https://sowaretokyo.github.io/GitEdit/appcast.xml)
#                   — SUFeedURL used by Sparkle
set -euo pipefail

APP_NAME="GitEdit"
BUNDLE_ID="co.jp.sowaretokyo.gitedit"
VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${APP_BUILD:-1}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://sowaretokyo.github.io/GitEdit/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="VAkwLqs3kd/a+rDGAeOfyWM6/s/phb/5GwWLA1sIkRo="

BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
FRAMEWORKS="${CONTENTS}/Frameworks"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES}" "${FRAMEWORKS}"

echo "==> Building universal release binary"
swift build -c release --arch arm64 --arch x86_64

# `--arch arm64 --arch x86_64` writes the lipo-joined binary under
# .build/apple/Products/Release/.
PRODUCTS_DIR=".build/apple/Products/Release"
cp "${PRODUCTS_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "==> Copying SPM resource bundles"
shopt -s nullglob
for bundle in "${PRODUCTS_DIR}"/*.bundle; do
    cp -R "${bundle}" "${RESOURCES}/"
done
shopt -u nullglob

echo "==> Copying SPM frameworks"
shopt -s nullglob
for framework in "${PRODUCTS_DIR}/Frameworks"/*.framework; do
    ditto "${framework}" "${FRAMEWORKS}/$(basename "${framework}")"
done
shopt -u nullglob

if ! otool -l "${MACOS_DIR}/${APP_NAME}" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}"
fi

echo "==> Generating AppIcon.icns from Resources/AppIcon.png"
SRC_PNG="Sources/GitEdit/Resources/AppIcon.png"
ICONSET="${BUILD_DIR}/AppIcon.iconset"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"
sips -z 16 16     "${SRC_PNG}" --out "${ICONSET}/icon_16x16.png"      > /dev/null
sips -z 32 32     "${SRC_PNG}" --out "${ICONSET}/icon_16x16@2x.png"   > /dev/null
sips -z 32 32     "${SRC_PNG}" --out "${ICONSET}/icon_32x32.png"      > /dev/null
sips -z 64 64     "${SRC_PNG}" --out "${ICONSET}/icon_32x32@2x.png"   > /dev/null
sips -z 128 128   "${SRC_PNG}" --out "${ICONSET}/icon_128x128.png"    > /dev/null
sips -z 256 256   "${SRC_PNG}" --out "${ICONSET}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "${SRC_PNG}" --out "${ICONSET}/icon_256x256.png"    > /dev/null
sips -z 512 512   "${SRC_PNG}" --out "${ICONSET}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "${SRC_PNG}" --out "${ICONSET}/icon_512x512.png"    > /dev/null
sips -z 1024 1024 "${SRC_PNG}" --out "${ICONSET}/icon_512x512@2x.png" > /dev/null
iconutil -c icns "${ICONSET}" -o "${RESOURCES}/AppIcon.icns"
rm -rf "${ICONSET}"

echo "==> Writing Info.plist (v${VERSION} build ${BUILD_NUMBER})"
cat > "${CONTENTS}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ja</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 株式会社ソワレ東京</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY}</string>
</dict>
</plist>
EOF

echo "✅ ${APP_DIR}"
