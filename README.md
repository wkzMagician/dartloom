# Dartloom

Dartloom is a convention-first toolkit for creating, checking, building, and releasing Flutter applications.

## Install

Requires Dart 3.10 or later:

```powershell
dart install https://github.com/wkzMagician/dartloom.git
```

Then run `dartloom --help`.

On Windows, add `%LOCALAPPDATA%\Dart\install\bin` to `PATH` if the command is not immediately found.

Update Dartloom itself at any time with:

```powershell
dartloom update
```

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

## Installers and Linux packages

From a generated application directory, Dartloom can create these release assets:

```powershell
dartloom package windows exe  # Setup.exe; requires Inno Setup on Windows
dartloom package windows zip  # portable ZIP
dartloom package windows msix # adds the `msix` dev dependency if needed
dartloom package linux deb    # Debian/Ubuntu; Linux host or CI runner
dartloom package linux rpm    # Red Hat/Fedora/Rocky/Alma; Linux host or CI runner
```

Windows EXE installers and portable ZIPs are suitable for GitHub Releases.
For public MSIX distribution, configure a trusted code-signing certificate;
unsigned MSIX is only appropriate for local testing. macOS DMG/PKG, iOS IPA,
Android installer formats, and web installers are not supported yet.

Prerequisites are intentionally platform-native: install Inno Setup (`iscc`) to
make a Windows EXE installer; install `dpkg-deb` for DEB; and install
`rpmbuild` (usually the `rpm-build` package) for RPM. Use GitHub's Windows and
Ubuntu runners to build the corresponding release assets in CI.

## Updating a generated app

Update the CLI first, then overwrite the Dartloom-managed files in an app:

```powershell
dart install --overwrite https://github.com/wkzMagician/dartloom.git
dartloom project update
```

`dartloom project update` overwrites `AGENTS.md`, Dartloom workflow wrappers, and the
capability glue file. It then upgrades enabled Dartloom capability packages and
runs checks. It never modifies `lib/features/` or application-specific code.
Use `dartloom project update --dry-run` to list files first, or
`dartloom project update --no-capabilities` to leave package versions unchanged.

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
