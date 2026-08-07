# Dartloom

Dartloom is a convention-first toolkit for creating, checking, building, and releasing Flutter applications.

## Install

Requires Dart 3.10 or later:

```powershell
dart install https://github.com/wkzMagician/dartloom.git --git-path cli/dartloom_cli
```

Then run `dartloom --help`.

On Windows, add `%LOCALAPPDATA%\Dart\install\bin` to `PATH` if the command is not immediately found.

## Capabilities

Use the terminal capability manager from inside a generated app:

```powershell
dartloom cap
dartloom cap list
dartloom cap add autostart
dartloom cap remove autostart
```

`dartloom cap` opens a keyboard-driven terminal UI. Use the up/down arrow keys
to move, Space to toggle capabilities, then select **保存并应用变更** with Space.
All additions and removals are applied as one batch before dependencies and
checks are run.

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
