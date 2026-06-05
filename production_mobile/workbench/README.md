# Virgil Workbench

Верстак для сборки автономного контента Virgil через текущий backend LEXO.

## Папки

- `input/` — исходные тексты и ручные json-файлы.
- `build/` — промежуточные результаты.
- `output/` — готовые файлы для переноса в bundled library или zip.

## Первый сценарий

1. Запустить backend LEXO.
2. Запустить `run_virgil_workbench.bat`.
3. Выбрать TXT.
4. Нажать `Import to backend`.
5. Нажать `Generate Kokoro package`.
6. Нажать `Export files`.

На выходе появится папка вида:

```text
output/a1/chapters/<book_id>/
  manifest.json
  load_manifest.json
  reader.json
  dictionary.json
  detail_manifest.json
  tts_manifest.json
  word_audio_manifest.json
  word_to_word.json
  audio/
    segments/
    words/
```

Также создаётся zip рядом с output-папкой и копируется в:

```text
assets/library/a1/<section>/books_zip/
```

Если Flutter снова выдаст CMake cache error после перемещения папок, запустить:

```text
run_virgil_workbench_clean.bat
```
