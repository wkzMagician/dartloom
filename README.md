# Dartloom

![Dart](https://img.shields.io/badge/Dart-%5E3.5.0-0175C2?logo=dart&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-%5E3.24.0-02569B?logo=flutter&logoColor=white)
[![Pub package validation](https://github.com/wkzMagician/dartloom/actions/workflows/pub_package_check.yml/badge.svg)](https://github.com/wkzMagician/dartloom/actions/workflows/pub_package_check.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Dartloom is a Flutter project configurator and Dart package monorepo. Its CLI creates and updates Flutter projects, selects Dartloom packages, checks project configuration, triggers cloud builds, and prepares tagged releases.

Dartloom packages are ordinary Dart and Flutter libraries. They provide contracts and adapters for capabilities such as storage, synchronization, settings, logging, localization, autostart, resident desktop apps, messaging, pairing, and single-instance behavior. Dartloom does not generate service locators, factories, dependency-registration code, or application business logic.

## Contents

- [Why Dartloom](#why-dartloom)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [CLI commands](#cli-commands)
- [Package catalog](#package-catalog)
- [Project files](#project-files)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Why Dartloom

- Start a Flutter project with a selected set of platforms and Dartloom packages.
- Keep the selection in `.dartloom/project.yaml` so it can be checked and reviewed.
- Use capability contracts independently from concrete implementations.
- Build supported Flutter targets in GitHub Actions and download workflow artifacts.
- Keep generated project documentation bounded to a managed section in `AGENTS.md`.

## Repository layout

| Path | Purpose |
| --- | --- |
| `cli/dartloom_cli` | The `dartloom` command-line executable and its tests |
| `packages/*` | Dart and Flutter capability contracts and adapters |
| `bricks/app` | Mason brick used by project generation |
| `workflows` | Workflow templates copied into generated projects |
| `.github/workflows` | CI, package validation, cloud build, and release workflows for this repository |
| `melos.yaml` | Dart monorepo package configuration |

## Getting started

### Prerequisites

- Dart SDK 3.5 or newer
- Flutter SDK 3.24 or newer
- `dart` and `flutter` available on `PATH`
- Git, for installation from this repository and for `build`/`release`

Verify the SDKs:

```bash
dart --version
flutter --version
```

### Install the CLI

Install the executable directly from GitHub:

```bash
dart pub global activate --source git \
  https://github.com/wkzMagician/dartloom.git \
  --git-path cli/dartloom_cli
```

Check that it is available:

```bash
dartloom --help
```

If the command is not found, add Dart's pub-cache executable directory to `PATH`. It is commonly `$HOME/.pub-cache/bin` on macOS/Linux and `%LOCALAPPDATA%\Pub\Cache\bin` on Windows.

To run the CLI from a checkout instead:

```bash
git clone https://github.com/wkzMagician/dartloom.git
cd dartloom/cli/dartloom_cli
dart pub get
dart run bin/dartloom.dart --help
```

### Create a project

Run `new` from the directory that should contain the generated project:

```bash
dartloom new my_app
```

You can select platforms and packages non-interactively:

```bash
dartloom new my_app --platforms=android,windows
dartloom new my_app --packages=dartloom_storage,dartloom_storage_file
```

The command runs `flutter create`, writes `.dartloom/project.yaml`, adds selected packages as direct dependencies, runs `flutter pub get`, updates the managed section of `AGENTS.md`, and adds the project workflow templates.

## CLI commands

| Command | What it does |
| --- | --- |
| `dartloom new <project-name>` | Creates a configured Flutter project. |
| `dartloom update` | Reopens configuration for the current project and synchronizes managed files. Removing a platform asks for confirmation before deleting its directory. |
| `dartloom check` | Performs a read-only validation of project configuration, selected packages, metadata, platform support, and generated documentation. |
| `dartloom build <platform\|all>` | Triggers `.github/workflows/dartloom-build.yml` for the current commit and downloads artifacts into `dist/<platform>/`. |
| `dartloom release [version]` | Updates the CLI package version when needed, creates an annotated `v<version>` tag, and pushes the release commit and tag. |

Build modes are `debug`, `profile`, and `release`; the default is `release`:

```bash
dartloom build windows
dartloom build android --mode profile
dartloom build all --mode release
```

`build` requires a clean working tree and a GitHub Actions workflow in the target project. It does not create GitHub Releases. `release` requires a clean working tree and uses the target project's release workflow when the pushed `v*` tag is built.

## Package catalog

The repository contains packages for the following capability areas:

| Area | Packages |
| --- | --- |
| Storage | `dartloom_storage`, `dartloom_storage_file`, `dartloom_storage_drift`, `dartloom_storage_indexeddb` |
| Synchronization | `dartloom_sync`, `dartloom_sync_etag`, `dartloom_sync_flutter`, `dartloom_sync_storage`, `dartloom_sync_webdav`, `dartloom_sync_workmanager` |
| Settings | `dartloom_settings`, `dartloom_settings_secure_storage`, `dartloom_settings_shared_preferences` |
| Logging | `dartloom_logging`, `dartloom_logging_logger` |
| Application capabilities | `dartloom_autostart`, `dartloom_autostart_launch_at_startup`, `dartloom_localization`, `dartloom_localization_gen_l10n`, `dartloom_messaging`, `dartloom_pairing`, `dartloom_resident`, `dartloom_resident_tray`, `dartloom_singleton`, `dartloom_singleton_socket` |
| External input | `dartloom_external_input`, `dartloom_external_input_android`, `dartloom_external_input_ios` |

The `dartloom_storage_json_file` and `dartloom_storage_text_file` packages remain in the repository as deprecated compatibility wrappers. New code should use the current object-storage APIs.

Each package stores deterministic metadata in `tool/dartloom-package.yaml`. The metadata records supported platforms and public exports for the CLI catalog; it is not AI-generated.

Example application code still owns composition and paths:

```dart
import 'package:dartloom_storage_file/dartloom_storage_file.dart';

final store = await FileObjectStore.open(root: directory);
```

The application may use constructor injection, Provider, Riverpod, GetIt, globals, or no dependency-injection mechanism at all.

## Project files

### `.dartloom/project.yaml`

The configuration contains only selected platforms and packages:

```yaml
platforms:
  - android
  - windows

packages:
  - dartloom_storage
  - dartloom_storage_file
```

It does not contain secrets, synchronization credentials, service registrations, factory IDs, or business models.

### `AGENTS.md`

Dartloom updates only the content between these markers:

```md
<!-- dartloom:begin -->
<!-- dartloom:end -->
```

User-authored content outside the markers is preserved.

### Generated workflows

Generated projects use `ci.yml` for formatting, analysis, and tests; `dartloom-build.yml` for platform builds and artifacts; and `release.yml` for tagged releases. Existing application source, project-owned workflow files, and installer files are not overwritten by `update`.

## Development

Install dependencies and run the CLI checks:

```bash
cd cli/dartloom_cli
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

The package-validation workflow runs the same kind of checks for selected packages, including `flutter analyze`, `flutter test`, and `flutter pub publish --dry-run`. Informational analyzer diagnostics do not fail CI.

When changing package dependencies in this monorepo, use a temporary `pubspec_overrides.yaml` for local workspace resolution and do not commit generated override files.

## Contributing

1. Fork the repository and create a focused branch.
2. Make the smallest change that addresses the issue.
3. Run the relevant formatter, analyzer, and tests.
4. Update package metadata or documentation when public behavior changes.
5. Open a pull request with the motivation and verification steps.

## License

Dartloom is distributed under the MIT License. See [LICENSE](LICENSE).

## Links

- [Repository](https://github.com/wkzMagician/dartloom)
- [Issue tracker](https://github.com/wkzMagician/dartloom/issues)
- [GitHub Actions](https://github.com/wkzMagician/dartloom/actions)
