#!/bin/zsh
# Собирает Dictation.app в папку build/. Запуск: ./build.sh  (или ./build.sh install — ещё и копия в /Applications)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

if [[ ! -f Resources/AppIcon.icns ]]; then
  TMP=$(mktemp -d)
  swift scripts/make_icon.swift "$TMP/icon.png"
  ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

APP=build/Dictation.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Dictation "$APP/Contents/MacOS/Dictation"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Локальный сертификат (создан 2026-11-15, лежит в связке «login»): подпись одинаковая у всех сборок,
# поэтому «Универсальный доступ» и микрофон не слетают после пересборки. Нет сертификата — ad-hoc.
IDENTITY="Dictation Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "⚠ сертификат «$IDENTITY» не найден — подпись ad-hoc (доступы придётся выдавать заново)"
  codesign --force --sign - "$APP"
fi
echo "Готово: $PWD/$APP"

if [[ "${1:-}" == "install" ]]; then
  rm -rf /Applications/Dictation.app
  cp -R "$APP" /Applications/
  echo "Установлено в /Applications/Dictation.app"
fi
