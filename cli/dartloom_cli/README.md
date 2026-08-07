# Dartloom

Dartloom is a convention-first CLI for creating and maintaining Flutter
applications. It keeps application code under your ownership while generating
and refreshing a small set of managed files.

## Install

After the package is published to pub.dev:

```sh
dart install dartloom
```

For repository development before that release:

```sh
dart install https://github.com/wkzMagician/dartloom.git --git-path cli/dartloom_cli
```

Use `dartloom --help` for the command reference. `dartloom cap` provides an
interactive terminal capability selector; `dartloom project update` directly
refreshes Dartloom-managed app files.

## Capability packages

Generated apps depend only on enabled capability packages, such as
`dartloom_settings` or `dartloom_storage`. These packages are public building
blocks, but app developers normally manage them exclusively with `dartloom cap`.

## Development

Run from this package directory:

```sh
dart pub get
dart analyze
dart test
dart pub publish --dry-run
```

The package is MIT licensed. See the repository for release workflows and
Windows/Linux installer support.
