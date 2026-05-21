#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.DerivedData}"
PRODUCT_DIR="${PRODUCT_DIR:-$ROOT_DIR/Product}"
DMG_ROOT="$PRODUCT_DIR/DmgRoot"
APP_NAME="${APP_NAME:-LyricsX}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$PRODUCT_DIR/$APP_NAME.dmg"

MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
CODE_SIGNING_REQUIRED="${CODE_SIGNING_REQUIRED:-NO}"
NOTARIZE="${NOTARIZE:-NO}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ "$NOTARIZE" == "YES" && ( "$CODE_SIGN_IDENTITY" == "-" || -z "$CODE_SIGN_IDENTITY" ) ]]; then
  echo "error: notarized distribution requires CODE_SIGN_IDENTITY='Developer ID Application: ...'" >&2
  exit 1
fi

if [[ "$NOTARIZE" == "YES" && -z "$NOTARY_PROFILE" ]]; then
  echo "error: notarized distribution requires NOTARY_PROFILE, created with xcrun notarytool store-credentials" >&2
  exit 1
fi

cd "$ROOT_DIR"
trap 'rm -rf "$DMG_ROOT"' EXIT

echo "==> Building Release app"
xcodebuild -quiet \
  -project "$ROOT_DIR/LyricsX.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
  CODE_SIGNING_REQUIRED="$CODE_SIGNING_REQUIRED" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Preparing DMG contents"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT" "$PRODUCT_DIR"
cp -R "$APP_PATH" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

if [[ "${SKIP_ADHOC_SIGN:-NO}" != "YES" ]]; then
  if [[ "$CODE_SIGN_IDENTITY" == "-" || -z "$CODE_SIGN_IDENTITY" ]]; then
    echo "==> Signing app for local use only"
    codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$DMG_ROOT/$APP_NAME.app"
  else
    echo "==> Signing app for Developer ID distribution"
    codesign --force --deep --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_ROOT/$APP_NAME.app"
    codesign --verify --deep --strict --verbose=2 "$DMG_ROOT/$APP_NAME.app"
    spctl --assess --type execute --verbose=2 "$DMG_ROOT/$APP_NAME.app" || true
  fi
fi

rm -f "$DMG_PATH"

echo "==> Creating DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "${SIGN_DMG:-$NOTARIZE}" == "YES" ]]; then
  echo "==> Signing DMG"
  codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$NOTARIZE" == "YES" ]]; then
  echo "==> Submitting DMG for notarization"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"

  echo "==> Gatekeeper assessment"
  spctl --assess --type open --verbose=2 "$DMG_PATH"
fi

echo "==> Done"
echo "$DMG_PATH"
