# LEXO / Virgil Workspace

This repository contains the complete source tree for the current LEXO/Virgil
reader, Windows Workbench, local backend and repository skills. Runtime books,
generated packages, model caches, credentials and compiled releases are created
locally and are intentionally not stored in Git.

## Requirements

- Windows 10/11 and PowerShell.
- Flutter SDK compatible with `Virgil/App/pubspec.yaml` (Dart 3.3 or newer).
- Visual Studio with the Desktop development with C++ workload for Workbench.
- Android Studio/Android SDK for Android builds.
- Python 3 for the local backend. Optional NLLB and Kokoro environments/models
  are local runtime resources; without them the launcher uses mock providers.

After cloning, run `flutter pub get` in `Virgil/App` once. The Workbench launcher
also runs it automatically when the package configuration is missing or stale.

## Main commands

- `START_VIRGIL.bat` - run the current Android development build.
- `START_WORKBENCH.bat` - start the backend and Virgil Workbench.
- `BUILD_RELEASE.bat` - build and package the Google Play AAB.
- `BUILD_IOS.bat` - push the current Virgil update and start the GitHub iOS build.

## Structure

- `Virgil/App/` - the only current Flutter application source.
- `Virgil/App/lib/src/workbench/` - Workbench UI and package-building logic.
- `Studio/Workbench/` - Workbench launchers, templates and local `Books/` input.
- `Studio/Backend/` - backend source; local models and databases live below
  `Studio/Backend/data/` and are not committed.
- `Skills/` - versioned Codex workflows, validators and their schemas.
- `Studio/Runtime/` - generated packages and local logs.
- `Studio/CloudLibrary/` - local mirror of the R2 book catalog.
- `Release/Builds/<version>/` - generated Google Play packages.
- `Release/iOS/` - downloaded IPA builds and the Sideloadly shortcut.
- `Release/PlayStore/` - descriptions, screenshots and declarations.
- `Private/` - local credentials, excluded from Git.
- `Archive/` - preserved legacy files, unused by current workflows.
- `Docs/History/` - project history and source-of-truth index.

## How Workbench is assembled

`START_WORKBENCH.bat` calls `Studio/Workbench/run_virgil_workbench.bat`. The
launcher starts `Studio/Backend/run_backend.bat`, then runs the same Flutter
project from `Virgil/App` with `VIRGIL_MODE=workbench`. The mode selector opens
the UI from `Virgil/App/lib/src/workbench/`; it is not a second application
stored inside `Studio/Workbench`.

Workbench reads source books and covers from the ignored
`Studio/Workbench/Books/` directory, builds packages under the ignored
`Studio/Runtime/` directory and maintains an ignored local R2 mirror in
`Studio/CloudLibrary/`. These directories are inputs or generated state, not
missing source code.

## Local configuration

Copy `Private/credentials.env.example` when credentials are needed and keep the
filled file in `Private/`. The directory is ignored except for the example.
Never commit signing keys, API keys or Cloudflare R2 credentials.

## Project maps

- `Virgil/App/README.md` - quick map of the active Flutter application.
- `Docs/VIRGIL_ARCHITECTURE.md` - detailed mobile, Workbench, package and dictionary data flows.
- `Studio/Workbench/README.md` - Workbench launch and storage locations.
- `Docs/History/INDEX.md` - chronological source-of-truth index for completed work.

## Release flow

1. Update `version` in `Virgil/App/pubspec.yaml`.
2. Test with `START_VIRGIL.bat`.
3. Run `BUILD_RELEASE.bat`.
4. Upload the AAB from `Release/Builds/<version>/` to Google Play.
