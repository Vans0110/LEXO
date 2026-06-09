# Virgil App

This is the only active Flutter application source.

Development:

```text
run_virgil_dev.bat
```

Google Play build:

```text
build_virgil_play_aab.bat
```

The release script reads the version from `pubspec.yaml` and creates:

```text
../../Release/Builds/<version>/
  Virgil-<version>.aab
  SHA256.txt
  certificate.txt
  release-notes.md
```
