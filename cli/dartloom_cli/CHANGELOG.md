# Changelog

## 0.2.5

- Install the Linux `libsecret-1-dev` dependency required by secure storage
  during generated CI and release builds.

## 0.2.4

- Keep Windows installer `MyAppVersion` synchronized during releases.

## 0.2.3

- Added cloud build and tagged release commands to the CLI.
- Improved project workflow generation, package selection, and configuration checks.

## 0.2.2

- Track the Dartloom `main` branch for GitHub capability dependencies and
  refresh dependency locks during project updates.
- Separate Dart project identifiers from distribution package and launcher
  names, including support for `dartloom new mini-todo`.

## 0.2.1

- Refresh Dartloom Git/package locks during project updates.
- Preserve application widgets and ARB translations during updates.
- Skip unsupported capability adapters at runtime and support nested options.

## 0.2.0

- Added schema v2 named capability instances and one-time v1 migration.
- Added runtime registry, official adapter selection, custom factories, and
  GitHub/pub.dev dependency switching.
- Replaced raw stdin parsing with a nested cross-platform terminal editor.

## 0.1.0

- Initial public release of the Dartloom CLI.
- Adds project generation, capability management, project updates, checks,
  builds, and Windows/Linux packaging commands.
