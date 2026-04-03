# Запуск MVP

Для запуска одним кликом используйте:

- [run_lexo_mvp.bat](/mnt/d/Programs/LEXO/run_lexo_mvp.bat)

## Что делает bat-файл

- проверяет наличие `Python` в `PATH`
- проверяет наличие `Flutter` в `PATH`
- при первом запуске выполняет `flutter pub get`
- поднимает `Python engine` в отдельном окне
- запускает `Flutter app` для `Windows`

## Что должно быть установлено в Windows

- `Python`
- `Flutter SDK`
- `Visual Studio Build Tools` или Visual Studio с workload для desktop C++

## Подключение NLLB внутри проекта

Если нужен реальный локальный перевод, а не mock-режим:

1. откройте `CMD`
2. перейдите в папку проекта `LEXO`
3. выполните:

```bat
setup_nllb.cmd
```

Скрипт:

- создаёт `.venv` внутри `LEXO`
- ставит Python-зависимости для `NLLB`
- скачивает модель в `data\models\nllb-200-distilled-600m\original`
- конвертирует её в `CTranslate2`-формат в `data\models\nllb-200-distilled-600m\ct2`

После этого `run_lexo_mvp.bat` будет поднимать engine через проектный `.venv` и включать режим `LEXO_TRANSLATOR=nllb`.

## Как запускать

Просто дважды нажмите:

- `run_lexo_mvp.bat`

## Если запуск не удался

Скопируйте текст ошибки из окна `.bat` или `Flutter` и пришлите его.
