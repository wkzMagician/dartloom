# dartloom_cli

The Dartloom CLI configures Flutter projects, manages their cloud-build
workflows, and selects normal Dart package dependencies. It provides
`dartloom new`, `dartloom update`, `dartloom check`, `dartloom build`, and
`dartloom release`.

`new` and `update` manage the project workflow files. `build` triggers
`.github/workflows/dartloom-build.yml` and downloads GitHub Actions artifacts.
`release` updates the package version, creates a release commit and `v*` tag,
and pushes the tag so the project's `release.yml` can build and publish it.

Applications own imports, object creation, dependency passing, paths, and
business behavior. The CLI never generates runtime registration or application
source code.
