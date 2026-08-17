# Dartloom

Dartloom is a Flutter project configurator and Dart package selector. It helps
you create a Flutter project with the platforms and Dartloom packages you want,
then keeps that selection documented and verifiable.

Dartloom does not provide a runtime framework. Your application still owns
imports, object creation, dependency passing, storage paths, business logic,
and runtime composition.

## Requirements

- Dart SDK 3.5 or newer
- Flutter SDK 3.24 or newer
- `flutter` available on your `PATH`

Check your environment with:

```bash
dart --version
flutter --version
```

## Install

Install the CLI directly from this GitHub repository:

```bash
dart pub global activate --source git \
  https://github.com/wkzMagician/dartloom.git \
  --git-path cli/dartloom_cli
```

Then verify the installation:

```bash
dartloom --help
```

If your shell cannot find `dartloom`, add Dart's pub-cache executable directory
to `PATH`. On most systems it is `$HOME/.pub-cache/bin`; on Windows it is
usually `%LOCALAPPDATA%\Pub\Cache\bin`.

To work from a checkout instead of installing globally:

```bash
git clone https://github.com/wkzMagician/dartloom.git
cd dartloom/cli/dartloom_cli
dart pub get
dart run bin/dartloom.dart --help
```

## Quick start

Create a project from the directory that should contain it:

```bash
dartloom new my_app
```

Dartloom opens an English terminal configuration UI. You select:

- Flutter platforms such as Android, iOS, Windows, macOS, Linux, and Web;
- optional Dartloom contract or implementation packages;
- package versions and dependency sources when those options are available.

After confirmation, Dartloom:

1. runs `flutter create` with the selected platforms;
2. creates the minimal application directories;
3. writes `.dartloom/project.yaml`;
4. adds selected Dartloom packages as direct `pubspec.yaml` dependencies;
5. runs `flutter pub get`;
6. generates the managed Dartloom section in `AGENTS.md`.

It also creates `.github/workflows/ci.yml`,
`.github/workflows/dartloom-build.yml`, `.github/workflows/release.yml`, and
the conventional `installer/windows.iss` entry point. The build workflow is
used for cloud artifacts; the release workflow builds the selected platforms
and publishes a GitHub Release for `v*` version tags. These workflows do not
generate service locators, factories, registration code, or feature code.

These are the two generally useful workflows for a new Flutter project:

- `ci.yml` checks formatting, analysis, and tests on pushes and pull requests.
- `dartloom-build.yml` builds one platform or all platforms through GitHub
  Actions and stores the results as workflow artifacts.
- `release.yml` builds the selected Flutter platforms and publishes tagged
  releases.

`installer/windows.iss` is a project-owned Inno Setup script. Dartloom uses
the generic filename but does not assume the application's name, AppId, icon,
or executable name. The release workflow can pass the release version to the
script without requiring Dartloom to parse or rewrite the installer file.

Additional workflows such as Dependabot, CodeQL, Pages, or a dedicated
localization workflow are optional and depend on the project; Dartloom does
not add them by default.

## Commands

### `dartloom new <project-name>`

Creates a new Flutter project and opens the configuration UI.

Examples:

```bash
dartloom new my_app
dartloom new my_app --platforms=android,windows
dartloom new my_app --packages=dartloom_storage,dartloom_storage_file
```

### `dartloom update <project-name>`

Reads the existing `.dartloom/project.yaml` and opens the same configuration UI.
It can add or remove selected packages, add Flutter platform files, update the
configuration, refresh `AGENTS.md`, add missing Dartloom workflows and the
generic Windows installer template, and run `flutter pub get`.

Removing a platform is destructive. Dartloom asks for confirmation before
deleting that platform's Flutter directory.

During update, Dartloom never overwrites existing application source or
project-owned workflow/installer files:

```text
lib/**
test/**
main.dart
.github/**
installer/**
```

### `dartloom build <platform|all>`

Triggers the committed `.github/workflows/dartloom-build.yml` on GitHub
Actions. It checks that the working tree is clean, builds the current commit,
waits for the workflow, and downloads artifacts into `dist/<platform>/`.

Examples:

```bash
dartloom build ios
dartloom build windows
dartloom build all
```

The command does not use local platform SDKs and does not create tags or
GitHub Releases. Run `dartloom update` first if the build workflow is missing.

### `dartloom release [version]`

Creates a release commit and an annotated `v<version>` tag, then pushes both
to `origin`. The pushed tag triggers the project's `.github/workflows/release.yml`,
which performs the formal multi-platform build and creates the GitHub Release.

Examples:

```bash
dartloom release
dartloom release 1.4.0
```

The working tree must be clean, and the release workflow must already exist.

### `dartloom check <project-name>`

Performs a read-only project check. It verifies that:

- `.dartloom/project.yaml` is valid;
- selected packages are direct `pubspec.yaml` dependencies;
- package metadata exists and is complete;
- selected packages support the selected Flutter platforms;
- the managed section of `AGENTS.md` is up to date.

It does not rewrite files, upgrade dependencies, or modify application source.

## Project configuration

Every configured project contains:

```text
.dartloom/project.yaml
```

Example:

```yaml
platforms:
  - android
  - windows

packages:
  - dartloom_storage
  - dartloom_storage_file
  - dartloom_settings
  - dartloom_settings_secure_storage
```

The file contains only platform and package selection. It does not contain
secrets, application paths, synchronization credentials, service registrations,
factory IDs, or business models.

## Package model

Dartloom packages are ordinary Dart libraries. For example, selecting
`dartloom_storage_file` only adds a dependency; your application decides how to
use it:

```dart
import 'package:dartloom_storage_file/dartloom_storage_file.dart';

final store = await FileObjectStore.open(root: directory);
```

The application may use Provider, Riverpod, GetIt, constructor injection,
globals, or no dependency-injection mechanism at all.

Every package provides deterministic English metadata in:

```text
tool/dartloom-package.yaml
```

The metadata describes supported platforms, package purpose, and public exports.
No AI-generated metadata is used.

## `AGENTS.md` generation

Dartloom replaces only the content between these markers:

```md
<!-- dartloom:begin -->
<!-- dartloom:end -->
```

All user-authored content outside the markers remains unchanged.

## Development

Run the CLI checks from `cli/dartloom_cli`:

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

The repository is organized as a Dart/Flutter monorepo. Package metadata is
stored next to each package, and the CLI package is named `dartloom_cli` while
the executable remains `dartloom`.
