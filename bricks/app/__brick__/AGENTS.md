# Agent Instructions

This project is managed by Dartloom. Read `dartloom.yaml` before changing
infrastructure. Feature code imports capability contracts and obtains configured
implementations through `Dartloom.get<T>(name: ...)`; it must not import adapter
packages directly. Register app-owned implementations by passing their factory
map to `bootstrapDartloom(customFactories: ...)`. Keep factories and business
code in application-owned files under `lib/features`. Call
`bootstrapDartloom()` from `lib/capabilities/bootstrap.dart` before
running the application's widget tree. Dartloom only owns files in
`lib/capabilities`; application widgets and ARB files remain application-owned.

Dartloom repository: https://github.com/wkzMagician/dartloom

## Dartloom commands

Install or refresh the CLI:

```bash
dart install --overwrite https://github.com/wkzMagician/dartloom.git --git-path cli/dartloom_cli
```

Upgrade Dartloom-managed project files and dependencies:

```bash
dartloom project upgrade
```

Check the project and build a Windows release package:

```bash
dartloom check
dartloom package windows exe
```

Before finishing, run `dart format .`, `flutter analyze`, and `flutter test`.
