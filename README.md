# LEXO / Virgil Workspace

## Main commands

- `START_VIRGIL.bat` - run the current Android development build.
- `START_WORKBENCH.bat` - start the backend and Virgil Workbench.
- `BUILD_RELEASE.bat` - build and package the Google Play AAB.
- `BUILD_IOS.bat` - push the current Virgil update and start the GitHub iOS build.

## Structure

- `Virgil/App/` - the only current Flutter application source.
- `Studio/Workbench/Books/` - source TXT files and covers.
- `Studio/Backend/` - backend source, local models and databases.
- `Studio/Runtime/` - generated packages and local logs.
- `Studio/CloudLibrary/` - local mirror of the R2 book catalog.
- `Release/Builds/<version>/` - generated Google Play packages.
- `Release/iOS/` - downloaded IPA builds and the Sideloadly shortcut.
- `Release/PlayStore/` - descriptions, screenshots and declarations.
- `Private/` - local credentials, excluded from Git.
- `Archive/` - preserved legacy files, unused by current workflows.
- `Docs/History/` - project history and source-of-truth index.

## Release flow

1. Update `version` in `Virgil/App/pubspec.yaml`.
2. Test with `START_VIRGIL.bat`.
3. Run `BUILD_RELEASE.bat`.
4. Upload the AAB from `Release/Builds/<version>/` to Google Play.
