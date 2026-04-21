#!/usr/bin/env bash
# Build and package a Tockk release.
#
# Usage:
#   scripts/release.sh 0.1.0
#
# Produces:
#   build/Tockk-<version>.dmg
#   build/homebrew/tockk.rb
#
# Optional environment variables:
#   TOCKK_RELEASE_BASE_URL   Override the GitHub release download base URL.
#   TOCKK_HOMEBREW_TAP_DIR   Copy the generated cask into <tap>/Casks/tockk.rb.
#   TOCKK_CODESIGN_IDENTITY  Developer ID Application identity for public distribution.
#   TOCKK_NOTARYTOOL_PROFILE Keychain profile name created by `xcrun notarytool store-credentials`.
#   TOCKK_NOTARY_APPLE_ID    Apple ID for notarization fallback.
#   TOCKK_NOTARY_PASSWORD    App-specific password for notarization fallback.
#   TOCKK_NOTARY_TEAM_ID     Apple Developer Team ID for notarization fallback.
#   TOCKK_SKIP_DMG_STYLING   Set to 1 to skip Finder window styling (useful on CI/headless sessions).
#
# Without a Developer ID identity this script falls back to a local-only,
# ad-hoc-signed build. Public DMG/Homebrew distribution should use both
# Developer ID signing and notarization.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>}"
APP_NAME="Tockk"
APP_BUNDLE="${APP_NAME}.app"
RELEASE_TAG="v${VERSION}"
DEFAULT_RELEASE_BASE_URL="https://github.com/somee4/tockk/releases/download/${RELEASE_TAG}"
RELEASE_BASE_URL="${TOCKK_RELEASE_BASE_URL:-$DEFAULT_RELEASE_BASE_URL}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
ARCHIVE_PATH="build/${APP_NAME}-${VERSION}.xcarchive"
EXPORT_DIR="build/export"
DMG_STAGE_DIR="build/dmg"
DMG_PATH="build/${DMG_NAME}"
DMG_RW_PATH="build/${APP_NAME}-${VERSION}-rw.dmg"
HOMEBREW_DIR="build/homebrew"
CASK_PATH="${HOMEBREW_DIR}/tockk.rb"
DOWNLOAD_URL="${RELEASE_BASE_URL}/${DMG_NAME}"
APP_PATH="${EXPORT_DIR}/${APP_BUNDLE}"
APP_NOTARY_ZIP_PATH="build/${APP_NAME}-${VERSION}-notarize.zip"
CODESIGN_IDENTITY="${TOCKK_CODESIGN_IDENTITY:-}"
NOTARYTOOL_PROFILE="${TOCKK_NOTARYTOOL_PROFILE:-}"
NOTARY_APPLE_ID="${TOCKK_NOTARY_APPLE_ID:-}"
NOTARY_PASSWORD="${TOCKK_NOTARY_PASSWORD:-}"
NOTARY_TEAM_ID="${TOCKK_NOTARY_TEAM_ID:-}"
NOTARIZATION_ENABLED=0
DMG_MOUNT_DIR=""
DMG_DEVICE=""

cd "$(dirname "${BASH_SOURCE[0]}")/.."

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

sign_path() {
  local path="$1"
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$CODESIGN_IDENTITY" \
    "$path"
}

sign_app_bundle() {
  local app_path="$1"
  local nested_path

  while IFS= read -r nested_path; do
    sign_path "$nested_path"
  done < <(
    find "$app_path/Contents" -depth \
      \( -name "*.app" -o -name "*.appex" -o -name "*.framework" -o -name "*.xpc" -o -name "*.dylib" \) \
      -print 2>/dev/null
  )

  sign_path "$app_path"
}

notarize_file() {
  local path="$1"

  if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
    xcrun notarytool submit "$path" \
      --keychain-profile "$NOTARYTOOL_PROFILE" \
      --wait
    return
  fi

  if [[ -n "$NOTARY_APPLE_ID" && -n "$NOTARY_PASSWORD" && -n "$NOTARY_TEAM_ID" ]]; then
    xcrun notarytool submit "$path" \
      --apple-id "$NOTARY_APPLE_ID" \
      --password "$NOTARY_PASSWORD" \
      --team-id "$NOTARY_TEAM_ID" \
      --wait
    return
  fi

  echo "error: notarization requested but no credentials were provided" >&2
  exit 1
}

cleanup_dmg_workdir() {
  if [[ -n "${DMG_DEVICE:-}" ]]; then
    hdiutil detach "$DMG_DEVICE" -quiet >/dev/null 2>&1 || \
      hdiutil detach "$DMG_DEVICE" -force -quiet >/dev/null 2>&1 || true
    DMG_DEVICE=""
  fi

  if [[ -n "${DMG_MOUNT_DIR:-}" && -d "$DMG_MOUNT_DIR" ]]; then
    rmdir "$DMG_MOUNT_DIR" 2>/dev/null || rm -rf "$DMG_MOUNT_DIR"
    DMG_MOUNT_DIR=""
  fi

  rm -f "$DMG_RW_PATH"
}

style_dmg_window() {
  local volume_name="$1"
  local app_bundle="$2"

  if [[ "${TOCKK_SKIP_DMG_STYLING:-0}" == "1" ]]; then
    echo "==> Skipping DMG styling (TOCKK_SKIP_DMG_STYLING=1)"
    return 0
  fi

  if ! command -v osascript >/dev/null 2>&1; then
    echo "warning: osascript is unavailable; leaving DMG with Finder defaults" >&2
    return 1
  fi

  if ! pgrep -x Finder >/dev/null 2>&1; then
    echo "warning: Finder is not running; leaving DMG with Finder defaults" >&2
    return 1
  fi

  echo "==> Styling DMG Finder window"
  osascript <<EOF
tell application "Finder"
  tell disk "${volume_name}"
    open
    delay 1
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {140, 120, 780, 430}

    set theViewOptions to the icon view options of theWindow
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set text size of theViewOptions to 14

    set position of item "${app_bundle}" of theWindow to {180, 170}
    set position of item "Applications" of theWindow to {460, 170}

    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
end tell
EOF
}

create_release_dmg() {
  local size_kb

  size_kb="$(du -sk "$DMG_STAGE_DIR" | awk '{print $1 + 20480}')"

  echo "==> Creating writable DMG"
  hdiutil create \
    -size "${size_kb}k" \
    -fs HFS+ \
    -volname "$APP_NAME" \
    -ov \
    "$DMG_RW_PATH"

  DMG_MOUNT_DIR="$(mktemp -d "/tmp/${APP_NAME}-dmg.XXXXXX")"

  echo "==> Mounting writable DMG"
  DMG_DEVICE="$(hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$DMG_MOUNT_DIR" \
    "$DMG_RW_PATH" | awk '/^\/dev\// {print $1; exit}')"

  if [[ -z "$DMG_DEVICE" ]]; then
    echo "error: failed to attach writable DMG" >&2
    exit 1
  fi

  echo "==> Copying staged files into DMG"
  cp -R "$DMG_STAGE_DIR/." "$DMG_MOUNT_DIR"

  if ! style_dmg_window "$APP_NAME" "$APP_BUNDLE"; then
    echo "warning: DMG window styling was skipped; the installer still works" >&2
  fi

  sync
  if command -v bless >/dev/null 2>&1; then
    bless --folder "$DMG_MOUNT_DIR" --openfolder "$DMG_MOUNT_DIR" >/dev/null 2>&1 || true
  fi

  echo "==> Finalizing writable DMG"
  hdiutil detach "$DMG_DEVICE"
  DMG_DEVICE=""
  rmdir "$DMG_MOUNT_DIR" 2>/dev/null || true
  DMG_MOUNT_DIR=""

  echo "==> Compressing release DMG"
  hdiutil convert \
    "$DMG_RW_PATH" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"
}

trap cleanup_dmg_workdir EXIT

require_command xcodegen
require_command xcodebuild
require_command hdiutil
require_command shasum

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  require_command codesign
  if [[ -n "$NOTARYTOOL_PROFILE" || -n "$NOTARY_APPLE_ID" || -n "$NOTARY_PASSWORD" || -n "$NOTARY_TEAM_ID" ]]; then
    require_command xcrun
    NOTARIZATION_ENABLED=1
  fi
elif [[ -n "$NOTARYTOOL_PROFILE" || -n "$NOTARY_APPLE_ID" || -n "$NOTARY_PASSWORD" || -n "$NOTARY_TEAM_ID" ]]; then
  echo "error: notarization credentials were provided but TOCKK_CODESIGN_IDENTITY is missing" >&2
  exit 1
fi

if [[ "$NOTARIZATION_ENABLED" -eq 1 ]]; then
  if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
    echo "==> Notarization auth: keychain profile ${NOTARYTOOL_PROFILE}"
  else
    if [[ -z "$NOTARY_APPLE_ID" || -z "$NOTARY_PASSWORD" || -z "$NOTARY_TEAM_ID" ]]; then
      echo "error: set TOCKK_NOTARYTOOL_PROFILE or all of TOCKK_NOTARY_APPLE_ID, TOCKK_NOTARY_PASSWORD, TOCKK_NOTARY_TEAM_ID" >&2
      exit 1
    fi
    echo "==> Notarization auth: Apple ID ${NOTARY_APPLE_ID}"
  fi
fi

echo "==> Cleaning previous release artifacts"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_STAGE_DIR" "$HOMEBREW_DIR"
rm -f "$DMG_PATH" "$DMG_RW_PATH" "$APP_NOTARY_ZIP_PATH"
find build -maxdepth 1 -type f -name "${APP_NAME}-*.zip" -delete 2>/dev/null || true

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Archiving ${APP_NAME} ${VERSION}"
xcodebuild \
  -scheme Tockk \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "==> Exporting ${APP_BUNDLE}"
mkdir -p "$EXPORT_DIR"
ditto "${ARCHIVE_PATH}/Products/Applications/${APP_BUNDLE}" "$APP_PATH"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  echo "==> Re-signing ${APP_BUNDLE} with Developer ID"
  sign_app_bundle "$APP_PATH"

  echo "==> Verifying signed app bundle"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"

  if [[ "$NOTARIZATION_ENABLED" -eq 1 ]]; then
    echo "==> Packaging app bundle for notarization"
    ditto -c -k --keepParent "$APP_PATH" "$APP_NOTARY_ZIP_PATH"
    echo "==> Notarizing signed app bundle"
    notarize_file "$APP_NOTARY_ZIP_PATH"
    echo "==> Stapling app bundle"
    xcrun stapler staple "$APP_PATH"
    rm -f "$APP_NOTARY_ZIP_PATH"
  fi
else
  echo "==> No TOCKK_CODESIGN_IDENTITY set; keeping Xcode's local ad-hoc signature"
fi

echo "==> Staging DMG contents"
mkdir -p "$DMG_STAGE_DIR"
ditto "$APP_PATH" "${DMG_STAGE_DIR}/${APP_BUNDLE}"
ln -s /Applications "${DMG_STAGE_DIR}/Applications"

create_release_dmg

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  echo "==> Signing DMG"
  sign_path "$DMG_PATH"

  if [[ "$NOTARIZATION_ENABLED" -eq 1 ]]; then
    echo "==> Notarizing DMG"
    notarize_file "$DMG_PATH"
    echo "==> Stapling DMG"
    xcrun stapler staple "$DMG_PATH"
  fi
fi

echo "==> Computing SHA256"
DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

echo "==> Writing Homebrew cask"
mkdir -p "$HOMEBREW_DIR"
cat >"$CASK_PATH" <<EOF
cask "tockk" do
  version "${VERSION}"
  sha256 "${DMG_SHA256}"

  url "${DOWNLOAD_URL}",
      verified: "github.com/somee4/tockk/"
  name "Tockk"
  desc "Notch-style notifications for local AI coding agent events"
  homepage "https://github.com/somee4/tockk"

  depends_on macos: ">= :ventura"

  app "${APP_BUNDLE}"
end
EOF

if [[ -n "${TOCKK_HOMEBREW_TAP_DIR:-}" ]]; then
  TAP_CASKS_DIR="${TOCKK_HOMEBREW_TAP_DIR%/}/Casks"
  echo "==> Copying cask into tap checkout"
  mkdir -p "$TAP_CASKS_DIR"
  cp "$CASK_PATH" "${TAP_CASKS_DIR}/tockk.rb"
fi

echo "==> Cleaning staging directories"
rm -rf "$EXPORT_DIR" "$DMG_STAGE_DIR"

echo ""
echo "✅ Release artifact: ${DMG_PATH}"
echo "✅ Homebrew cask: ${CASK_PATH}"
if [[ -n "$CODESIGN_IDENTITY" ]]; then
  echo "✅ App signing identity: ${CODESIGN_IDENTITY}"
  if [[ "$NOTARIZATION_ENABLED" -eq 1 ]]; then
    echo "✅ Notarization: completed and stapled"
  else
    echo "⚠️  Notarization: skipped (set TOCKK_NOTARYTOOL_PROFILE or Apple ID env vars)"
  fi
else
  echo "⚠️  Signing: local-only ad-hoc signature. Public DMG/Homebrew release should set TOCKK_CODESIGN_IDENTITY."
fi
echo "Next:"
echo "  1. Upload ${DMG_NAME} to GitHub Releases tag ${RELEASE_TAG}"
echo "  2. Commit the generated cask into your tap repo or submit it to Homebrew"
