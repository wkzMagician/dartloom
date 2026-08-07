# Dartloom

Dartloom is a convention-first toolkit for creating, checking, building, and releasing Flutter applications.

## Install

Requires Dart 3.10 or later:

```powershell
dart install https://github.com/wkzMagician/dartloom.git --git-path cli/dartloom_cli
```

Then run `dartloom --help`.

On Windows, add `%LOCALAPPDATA%\Dart\install\bin` to `PATH` if the command is not immediately found.

## Development

```powershell
cd cli/dartloom_cli
dart pub get
dart test
dart run bin/dartloom.dart --help
```

Run the CLI from the repository root while developing:

```powershell
dart run cli/dartloom_cli/bin/dartloom.dart new demo --platforms=android,windows --capabilities=settings,storage,logging
```

The generated app owns business code in `lib/features`; reusable infrastructure belongs in `packages`.
