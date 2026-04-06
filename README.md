# LEXO

Первая итерация локального MVP:

- `engine/` — Python local engine с HTTP API на `localhost`
- `app/` — Flutter desktop UI-каркас
- `data/` — локальные данные книги, SQLite, кэш и логи

## Что уже есть

- импорт `.txt` книги
- разбиение на абзацы
- хранение текущей книги в `SQLite`
- сохранение позиции чтения
- lookup слова с локальным кэшем
- сохранение слов в словарь
- каркас экранов `Home`, `Reader`, `Saved Words`
- Windows desktop bootstrap для Flutter app

## Чего пока нет

- реальный офлайн-перевод
- реальный TTS
- проверка Flutter UI рантаймом в текущем окружении

## Запуск engine

```bash
python3 -m engine.main
```

API по умолчанию поднимается на `http://127.0.0.1:8765`.

## Запуск app на Windows

Нужно, чтобы были установлены Flutter SDK и Visual Studio Build Tools для Windows desktop.

```bash
cd app
flutter pub get
flutter config --enable-windows-desktop
flutter run -d windows
```

## Запуск одним кликом

Для mobile/shared LAN host:

- `run_lexo_engine_lan.bat`

Для Windows UI с подключением к уже запущенному host:

- `run_lexo_windows_ui_lan.bat`

Старый combined desktop launcher сохранён как legacy-вариант:

- `scripts/run_lexo_mvp.bat`
