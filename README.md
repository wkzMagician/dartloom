# Dartloom

Dartloom is a Flutter project configurator and Dart package selector. It records
only selected Flutter platforms and direct Dartloom package dependencies; runtime
composition remains owned by the application.

## Commands

```bash
dartloom new my_app
dartloom update my_app
dartloom check my_app
```

`new` and `update` use the same English terminal configuration UI. A configured
project stores its selection in `.dartloom/project.yaml`. `check` is read-only:
it validates the configuration, package metadata, direct dependencies, platform
support, and the managed section of `AGENTS.md`.

Dartloom never generates service locators, factories, runtime registration,
application feature code, CI workflows, or changes to `main.dart` during update.

## Package metadata

Every package provides deterministic metadata at
`tool/dartloom-package.yaml`. The CLI uses that metadata to validate selections
and generate the section between `<!-- dartloom:begin -->` and
`<!-- dartloom:end -->` in `AGENTS.md`.
