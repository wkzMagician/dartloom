# dartloom_cli

The Dartloom CLI configures Flutter projects, manages their cloud-build
workflows, selects normal Dart package dependencies, and initializes GitHub
governance through the `gh-repoflow` extension. It provides
`dartloom new`, `dartloom update`, `dartloom check`, `dartloom build`, and
`dartloom release`.

Only `new` takes a project name. `update`, `check`, `build`, and `release` run
in the current project directory. `new` and `update` manage the project workflow files. `build` triggers
`.github/workflows/dartloom-build.yml` and downloads GitHub Actions artifacts.
`release` updates the package version, creates a release commit and `v*` tag,
and pushes the tag so the project's `release.yml` can build and publish it.

`build` accepts `--mode debug|profile|release`; the default is `release`.

Applications own imports, object creation, dependency passing, paths, and
business behavior. The CLI never generates runtime registration or application
source code.
