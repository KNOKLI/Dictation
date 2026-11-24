# Dictation

Локальная диктовка на русском для macOS. Распознавание идёт прямо на Mac (whisper.cpp, модель
large-v3-turbo), без интернета и без отправки голоса куда-либо.

- Правый ⌘ в любом приложении — начать и закончить диктовку, текст сам вставится туда, где курсор.
- История записей с поиском, свой словарь и автозамены, голосовые команды («новая строка», «запятая»…).
- Статистика: сколько символов надиктовано сегодня, за неделю и всего.

**Нужно:** Mac на Apple Silicon (M1 и новее), macOS 26 или новее, [Homebrew](https://brew.sh).

## Установка

Одной командой в Терминале:

```bash
curl -fsSL https://raw.githubusercontent.com/KNOKLI/Dictation/main/install.sh | bash
```

Скрипт поставит движок распознавания (`brew install whisper-cpp`), скачает последнюю версию
из [Releases](https://github.com/KNOKLI/Dictation/releases) в «Программы» и запустит её.

### Вручную

1. `brew install whisper-cpp`
2. Скачай `Dictation.zip` в [Releases](https://github.com/KNOKLI/Dictation/releases/latest), распакуй
   и перетащи `Dictation.app` в «Программы».
3. Приложение подписано не через Apple, поэтому при первом запуске macOS его остановит. Открой его так:
   правый клик по `Dictation.app` → «Открыть» → «Открыть». Или в Терминале:
   `xattr -dr com.apple.quarantine /Applications/Dictation.app`

### Первый запуск

- Приложение само скачает модель распознавания (~550 МБ) в `~/Library/Application Support/Dictation/`.
- Разреши доступ к **микрофону**.
- Для правого ⌘ в других приложениях и автовставки текста разреши **«Универсальный доступ»**
  (Системные настройки → Конфиденциальность и безопасность → Универсальный доступ).

## Сборка из исходников

```bash
brew install whisper-cpp
./build.sh            # → build/Dictation.app
./build.sh install    # → ещё и в /Applications
```

`build.sh` подписывает приложение локальным сертификатом «Dictation Local Signing», если он есть,
иначе — ad-hoc подписью.
