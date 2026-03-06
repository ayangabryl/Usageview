#!/bin/bash
set -euo pipefail

#───────────────────────────────────────────────────────────────────────────────
# QuotaBar — DMG Installer Builder
#
# Prerequisites:
#   brew install create-dmg
#
# Usage:
#   ./Scripts/build-dmg.sh            # builds Release .app then packages DMG
#   ./Scripts/build-dmg.sh --skip-build  # package DMG from existing build
#───────────────────────────────────────────────────────────────────────────────

APP_NAME="QuotaBar"
SCHEME="QuotaBar"
CONFIG="Release"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
DMG_DIR="${BUILD_DIR}/dmg"
APP_PATH="${DMG_DIR}/${APP_NAME}.app"

# Get version from Xcode project
VERSION=$(grep 'MARKETING_VERSION' "${PROJECT_DIR}/QuotaBar.xcodeproj/project.pbxproj" \
    | head -1 | sed 's/.*= //' | sed 's/;//' | tr -d '[:space:]')
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║           QuotaBar DMG Builder                   ║"
echo "║           Version: ${VERSION}                        ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Step 0: Check dependencies ──────────────────────────────────────────────
if ! command -v create-dmg &>/dev/null; then
    echo "❌ create-dmg not found. Install with: brew install create-dmg"
    exit 1
fi

# ── Step 1: Build the app ───────────────────────────────────────────────────
SKIP_BUILD=false
if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=true
fi

if [[ "$SKIP_BUILD" == false ]]; then
    echo "🔨 Building ${APP_NAME} (${CONFIG})..."

    # Use Developer ID signing if available (CI), otherwise ad-hoc for local dev
    if [[ -n "${CODE_SIGN_IDENTITY:-}" && -n "${TEAM_ID:-}" ]]; then
        echo "🔐 Code signing with: ${CODE_SIGN_IDENTITY}"

        # Determine keychain flags (CI uses a temporary keychain)
        KEYCHAIN_FLAGS=""
        if [[ -n "${KEYCHAIN_NAME:-}" ]]; then
            KEYCHAIN_FLAGS="--keychain ${KEYCHAIN_NAME}"
        fi

        xcodebuild \
            -scheme "$SCHEME" \
            -configuration "$CONFIG" \
            -derivedDataPath "${BUILD_DIR}/DerivedData" \
            -arch arm64 -arch x86_64 \
            ONLY_ACTIVE_ARCH=NO \
            CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}" \
            DEVELOPMENT_TEAM="${TEAM_ID}" \
            CODE_SIGN_STYLE="Manual" \
            CODE_SIGN_ENTITLEMENTS="" \
            PROVISIONING_PROFILE_SPECIFIER="" \
            PROVISIONING_PROFILE="" \
            ENABLE_HARDENED_RUNTIME=YES \
            ENABLE_APP_SANDBOX=NO \
            OTHER_CODE_SIGN_FLAGS="${KEYCHAIN_FLAGS}" \
            clean build
    else
        echo "⚠️  No signing identity — using ad-hoc signature (local dev)"
        xcodebuild \
            -scheme "$SCHEME" \
            -configuration "$CONFIG" \
            -derivedDataPath "${BUILD_DIR}/DerivedData" \
            -arch arm64 -arch x86_64 \
            ONLY_ACTIVE_ARCH=NO \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            clean build 2>&1 | tail -3
    fi

    echo "✅ Build succeeded"
else
    echo "⏩ Skipping build (--skip-build)"
fi

# ── Step 2: Locate and copy .app ────────────────────────────────────────────
echo "📦 Preparing DMG staging area..."

BUILT_APP=$(find "${BUILD_DIR}/DerivedData" -name "${APP_NAME}.app" -type d \
    -path "*/Release/*" 2>/dev/null | head -1)

if [[ -z "$BUILT_APP" ]]; then
    echo "❌ Could not find ${APP_NAME}.app in build output"
    echo "   Searched in: ${BUILD_DIR}/DerivedData"
    exit 1
fi

rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$BUILT_APP" "$APP_PATH"

echo "   App: $(du -sh "$APP_PATH" | cut -f1) → ${APP_PATH}"

# ── Step 3: Build the DMG ────────────────────────────────────────────────────
echo "💿 Creating DMG..."

# Remove existing DMG if present
rm -f "$DMG_PATH"

# Build .icns from app icon PNGs for the volume icon (title bar)
ICON_DIR="${BUILD_DIR}/icon.iconset"
ICNS_PATH="${BUILD_DIR}/VolumeIcon.icns"
ICON_SRC="${PROJECT_DIR}/QuotaBar/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"
cp "${ICON_SRC}/icon_16x16.png"     "${ICON_DIR}/icon_16x16.png"
cp "${ICON_SRC}/icon_32x32.png"     "${ICON_DIR}/icon_16x16@2x.png"
cp "${ICON_SRC}/icon_32x32.png"     "${ICON_DIR}/icon_32x32.png"
cp "${ICON_SRC}/icon_64x64.png"     "${ICON_DIR}/icon_32x32@2x.png"
cp "${ICON_SRC}/icon_128x128.png"   "${ICON_DIR}/icon_128x128.png"
cp "${ICON_SRC}/icon_256x256.png"   "${ICON_DIR}/icon_128x128@2x.png"
cp "${ICON_SRC}/icon_256x256.png"   "${ICON_DIR}/icon_256x256.png"
cp "${ICON_SRC}/icon_512x512.png"   "${ICON_DIR}/icon_256x256@2x.png"
cp "${ICON_SRC}/icon_512x512.png"   "${ICON_DIR}/icon_512x512.png"
cp "${ICON_SRC}/icon_1024x1024.png" "${ICON_DIR}/icon_512x512@2x.png"
iconutil -c icns "$ICON_DIR" -o "$ICNS_PATH"

# Build codesign flag for the DMG itself
DMG_CODESIGN_FLAGS=()
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    DMG_CODESIGN_FLAGS+=(--codesign "${CODE_SIGN_IDENTITY}")
fi

create-dmg \
    --volname "${APP_NAME}" \
    --volicon "$ICNS_PATH" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 128 \
    --icon "${APP_NAME}.app" 150 180 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 390 180 \
    --icon ".VolumeIcon.icns" 999 999 \
    --text-size 14 \
    --no-internet-enable \
    "${DMG_CODESIGN_FLAGS[@]}" \
    "$DMG_PATH" \
    "$DMG_DIR"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✅ DMG created successfully!"
echo "  📍 ${DMG_PATH}"
echo "  📏 $(du -sh "$DMG_PATH" | cut -f1)"
echo "═══════════════════════════════════════════════════"
echo ""
