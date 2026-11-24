#!/bin/bash
# Установка Dictation одной командой:
#   curl -fsSL https://raw.githubusercontent.com/KNOKLI/Dictation/main/install.sh | bash
# (для приватного репозитория — через GitHub CLI: gh auth login, потом запустить этот скрипт)
set -euo pipefail

REPO="KNOKLI/Dictation"
APP="/Applications/Dictation.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Dictation: локальная диктовка на русском"

# 1. macOS 26+ и Apple Silicon
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Нужен Mac на Apple Silicon (M1 и новее)." >&2; exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 26 )); then
    echo "Нужна macOS 26 или новее." >&2; exit 1
fi

# 2. Скачиваю последнюю версию (движок распознавания уже внутри - Homebrew не нужен, 2026-11-25)
echo "→ Скачиваю приложение…"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    gh release download --repo "$REPO" --pattern "Dictation.zip" --dir "$TMP"
else
    curl -fL --progress-bar "https://github.com/$REPO/releases/latest/download/Dictation.zip" -o "$TMP/Dictation.zip"
fi

# 3. Ставлю в «Программы»
osascript -e 'quit app "Dictation"' >/dev/null 2>&1 || true
ditto -x -k "$TMP/Dictation.zip" "$TMP"
rm -rf "$APP"
mv "$TMP/Dictation.app" "$APP"
# приложение подписано локально, не через Apple — снимаю пометку «скачано из интернета»
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✓ Готово: $APP"
echo "  При первом запуске приложение скачает модель распознавания (~550 МБ)"
echo "  и попросит доступ к микрофону и «Универсальному доступу»."
open "$APP"
