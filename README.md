# Dartloom

Dartloom is a convention-first toolkit for creating, checking, building, and
releasing Flutter applications.

## Install

The public package name is `dartloom`. It is prepared for pub.dev publication,
but is not published yet. After the first pub.dev release, installation will be:

```powershell
dart install dartloom
```

Until then, install the development build from Git:

```powershell
dart install https://github.com/wkzMagician/dartloom.git --git-path cli/dartloom_cli
```

Then run `dartloom --help`. On Windows, add
`%LOCALAPPDATA%\Dart\install\bin` to `PATH` if the command is not immediately
found.

Update Dartloom itself with `dartloom update`. Before the package is available
on pub.dev, a Git-installed development build must opt into Git updates:

```powershell
$env:DARTLOOM_UPDATE_SOURCE = 'git'
dartloom update
```

## Capabilities

Use the terminal capability manager from inside a generated app:

```powershell
dartloom cap
dartloom cap list
dartloom cap add autostart
dartloom cap remove autostart
dartloom cap add localization
dartloom cap add resident
```

`dartloom cap` opens a keyboard-driven terminal UI. Use the up/down arrow keys
to move, Space to toggle capabilities, then select **Save and apply changes**
with Space. All additions and removals are applied as one batch before
dependencies and checks are run. Available capability names include
`localization` and `resident`.

Each capability is an independent pub.dev package (`dartloom_settings`,
`dartloom_storage`, and so on). Generated apps only depend on selected
capabilities; users do not install those packages manually. The shared pub cache
means multiple apps reuse downloaded versions. Before those packages are
published, Git-based development can opt into Git dependencies:

```powershell
$env:DARTLOOM_CAPABILITY_SOURCE = 'git'
dartloom new demo
```

`localization` wires Flutter locale delegates for English and Chinese into the
generated app shell; app messages can then use Flutter's standard ARB workflow.
`resident` is a desktop
capability for Windows, macOS, and Linux. It exposes a controller that hides a
window when the user closes it and restores/quits it from the system tray or
menu bar. It uses `tray_manager` and `window_manager`; Linux tray support may
require an AppIndicator package supplied by the target distribution.

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

Prerequisites are platform-native: install Inno Setup (`iscc`) for Windows EXE;
install `dpkg-deb` for DEB; and install `rpmbuild` (usually `rpm-build`) for
RPM. GitHub's Windows and Ubuntu runners can build the corresponding release
assets in CI.

## Updating a generated app

Update the CLI first, then overwrite Dartloom-managed files in an app:

```powershell
# After pub.dev publication:
dartloom update

# For the current Git development build:
$env:DARTLOOM_UPDATE_SOURCE = 'git'
dartloom update

dartloom project update
```

`dartloom project update` overwrites `AGENTS.md`, the Dartloom app shell,
workflow wrappers, and the capability glue file. It then upgrades enabled Dartloom capability
packages and runs checks. It never modifies `lib/features/` or
application-specific code. Use `dartloom project update --dry-run` to list
files first, or `dartloom project update --no-capabilities` to leave package
versions unchanged.

## Development

```powershell
cd cli/dartloom_cli
dart pub get
dart analyze
dart test
dart pub publish --dry-run
```

Run the CLI from the repository root while developing:

```powershell
dart run cli/dartloom_cli/bin/dartloom.dart new demo --platforms=android,windows --capabilities=settings,storage,logging
```

Before publication, set `DARTLOOM_CAPABILITY_SOURCE=git` when creating a
project outside this repository. The generated app owns business code in
`lib/features`; reusable infrastructure belongs in `packages`.

## Publishing plan

No package is published by this repository yet. The release order will be the
seven capability packages first, followed by `dartloom`. Each package has its
own `README.md`, `CHANGELOG.md`, `LICENSE`, repository metadata, tests, and
`dart pub publish --dry-run` validation target.
