# Virgil App

`Virgil/App` is the only active Flutter application source in LEXO. The same
entrypoint runs the Android/iOS reader and the Windows Workbench.

## Entry and modes

- `lib/main.dart` initializes Flutter, MediaKit and background audio.
- `lib/src/app.dart` selects the application mode through `VIRGIL_MODE`.
- `VIRGIL_MODE=mobile` opens `MobileShellScreen`.
- `VIRGIL_MODE=workbench` opens `VirgilWorkbenchScreen`.

## Main commands

Run the Android development build from the workspace root:

```text
START_VIRGIL.bat
```

Run Workbench and its backend:

```text
START_WORKBENCH.bat
```

Build the Google Play release:

```text
BUILD_RELEASE.bat
```

The release script reads `version` from `pubspec.yaml` and creates:

```text
../../Release/Builds/<version>/
  Virgil-<version>.aab
  SHA256.txt
  certificate.txt
  release-notes.md
```

## Source map

- `lib/src/ui/mobile/screens/` - Library, book details, Reader, Cards and Settings.
- `lib/src/ui/mobile/widgets/` - mobile presentation widgets.
- `lib/src/mobile/` - downloaded-book storage, package parsing, cards, settings and audio.
- `lib/src/workbench/` - Windows book builder, package status and R2 publishing UI.
- `lib/src/widgets/` - shared reader/detail/playback widgets.
- `lib/src/models.dart` - shared reader and detail-sheet models.
- `lib/src/detail_sheet_models.dart` - construction of word/phrase detail cards.
- `lib/src/api/` - client for the local Studio backend.
- `test/` - Flutter regression and interaction tests.

## Main mobile flow

1. Library loads `library_index.json` from the configured cloud catalog.
2. A selected book ZIP is downloaded and unpacked into local application storage.
3. The repository creates/reads local `package.json` and selects the preferred
   `reader_<lang>.json`, `dictionary_<lang>.json` and
   `word_to_word_<lang>.json` payloads.
4. Reader renders the source text and uses the selected package entirely offline.

## Dictionary contract

- `dictionary_<lang>.json` is the book slice of the Global dictionaries. It is
  the source for translations shown in the `Words` section of a detail card.
- `word_to_word_<lang>.json` describes occurrence-level contextual alignment,
  tap ownership, target spans and phrase/grammar grouping. It supplies the
  contextual card header and parallel-text highlighting.
- The mobile app must not invent or hardcode translations for individual words.
- Workbench refresh is one-way: Globals -> book dictionary -> word-to-word.
  Refresh must not write book data back into Globals.

See [`../../Docs/VIRGIL_ARCHITECTURE.md`](../../Docs/VIRGIL_ARCHITECTURE.md)
for the full architecture and data ownership map.
