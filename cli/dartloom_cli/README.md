# Dartloom CLI

Configuration-driven lifecycle tooling for Dartloom Flutter applications.

```bash
dart install --overwrite https://github.com/wkzMagician/dartloom.git --git-path cli/dartloom_cli
dartloom new my_app
cd my_app
dartloom cap
```

After pub.dev publication, install with `dart install dartloom`. Use
`dartloom update` to refresh the CLI and `dartloom project update` to migrate
schema v1 or overwrite Dartloom-managed application glue.

The interactive `dartloom cap` editor manages named capability instances,
official/custom implementations, adapter options, sync storage selection, and
WebDAV configuration. `${NAME}` options become required Dart defines.

Use `dartloom source github` during repository development and
`dartloom source pub` after selected packages are available on pub.dev. Run
`dartloom --help` for build, installer, and unsupported-platform details.
