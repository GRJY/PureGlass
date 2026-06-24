#!/usr/bin/env bash
# PureGlass — Release derlemesi + DMG üretimi.
# Kullanım: ./scripts/build-release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PureGlass"
CONFIG="Release"
BUILD_DIR="build"

echo "▶︎ XcodeGen ile proje üretiliyor…"
xcodegen generate >/dev/null

echo "▶︎ $CONFIG derleniyor…"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR/dd" \
  -destination 'generic/platform=macOS' \
  build >/dev/null

APP_PATH="$BUILD_DIR/dd/Build/Products/$CONFIG/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "✗ Uygulama bulunamadı: $APP_PATH" >&2
  exit 1
fi
echo "✅ Uygulama: $APP_PATH"

echo "▶︎ DMG paketleniyor…"
DMG_STAGE="$BUILD_DIR/dmg"
DMG_OUT="$BUILD_DIR/$APP_NAME.dmg"
rm -rf "$DMG_STAGE" "$DMG_OUT"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov -format UDZO \
  "$DMG_OUT" >/dev/null

echo "✅ DMG: $DMG_OUT"
echo
echo "Kurulum: DMG'yi aç, PureGlass'i Applications'a sürükle."
echo "İlk açılış (imzasız): Finder'da sağ tık → Aç → Aç (Gatekeeper uyarısını geç)."
