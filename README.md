# Dartloom

Dartloom is a configuration-driven capability framework and CLI for Flutter
applications. Feature code depends on stable contracts; `dartloom.yaml` selects
the production adapters installed and registered at startup.

## Install

Before the CLI is published to pub.dev:

```bash
dart install --overwrite https://github.com/wkzMagician/dartloom.git --git-path cli/dartloom_cli
```

After publication:

```bash
dart install dartloom
```

Update the installed CLI with `dartloom update`.

## Create and configure an application

```bash
dartloom new my_app --platforms=android,windows
cd my_app
dartloom cap
dartloom cap list
dartloom cap add localization
dartloom cap remove localization
```

Hyphenated distribution names are supported. Dartloom keeps the output and
package name separate from the Dart identifier, so `dartloom new mini-todo`
creates the `mini-todo/` directory with Dart project name `mini_todo` and
distribution package name `mini-todo`.

```yaml
app:
  name: mini_todo
  package_name: mini-todo
```

`dartloom cap` is a keyboard-driven terminal editor. Use Up/Down to move,
Space to enable or disable, Enter to edit implementations and options, and the
Save row to apply the complete dependency change once.

Generated feature code obtains configured services from the runtime registry:

```dart
final settings = Dartloom.get<SettingsStore>();
final json = Dartloom.get<JsonStore>(name: 'json');
```

Application-owned adapters use a factory ID in `dartloom.yaml` and are supplied
to `initializeDartloom(customFactories: {...})`. Feature code should never
import adapter packages directly.

## Capability catalog

| Capability | Stable contract | Official implementation |
| --- | --- | --- |
| settings | portable settings values | shared_preferences, secure_storage |
| storage.text | UTF-8 text CRUD | atomic files |
| storage.json | JSON value CRUD | atomic JSON file |
| storage.database | collection/id document CRUD | Drift/SQLite |
| logging | application logger | logger |
| autostart | enable/disable startup | launch_at_startup |
| localization | locales and delegates | Flutter gen-l10n |
| resident | close-to-tray lifecycle, menus, and exit policy | tray_manager + window_manager |
| sync | object sync and conflicts | ETag engine + WebDAV backend |

Sync only reads storage instances explicitly listed in its configuration. It
uses conditional ETag writes, persists tombstones and common bases, preserves
conflicts by default, and accepts an application-specific merge factory.

## Configuration and secrets

Schema version 3 stores named instances, typed sync policies, platform
overrides, and adapter options. Dartloom-owned
storage categories are intentionally generic: `text`, `json`, and `database`.
Business-specific names such as “notes” do not appear in the framework catalog.

```yaml
capabilities:
  storage:
    instances:
      json:
        implementation: json_file
        options:
          path: dartloom/data.json
  autostart:
    instances:
      default:
        implementation: launch_at_startup
        platforms: [windows, macos, linux]
  sync:
    instances:
      default:
        implementation: etag
        policy:
          mode: automatic
        stores: [storage.json]
        backend:
          implementation: webdav
          options:
            root_path: Dartloom
```

`${NAME}` becomes a required `--dart-define=NAME=...`; secrets are never copied
into generated Dart source. Run `dartloom project update` once to migrate a
schema version 1 project. It only overwrites Dartloom-owned capability glue
(`lib/capabilities`), never application widgets or existing ARB translations,
and always runs `flutter pub upgrade` so Git dependency locks match the
generated contract API. GitHub mode explicitly tracks Dartloom's `main`
branch; each `dartloom project update` refreshes the lockfile to its latest
compatible commit.

Desktop-only adapters such as `resident` are registered only on supported
desktop targets. A mixed Android/Windows application can therefore keep one
configuration without initializing a tray adapter on Android. An instance-level
`platforms` list can narrow registration further, and optional UI can use
`Dartloom.maybeGet<T>()` instead of repeating operating-system checks.
Configure the resident menu, click actions, and exit callback through the contract:

```dart
final resident = Dartloom.get<ResidentService>();
await resident.configure(ResidentConfiguration(
  menu: const [
    ResidentMenuItem.action(id: 'quit', label: 'Quit completely'),
  ],
  leftClick: ResidentClickAction.showMenu,
  onExitRequested: () async => true,
));
```

## GitHub development and pub.dev release

```bash
dartloom source github  # hosted constraints plus Git/path overrides
dartloom source pub     # hosted pub.dev dependencies, no overrides
```

GitHub mode works before the packages are published. For pub.dev, publish
contracts first, then runtime/adapters, and finally the CLI. Every package has
hosted internal constraints and supports `dart pub publish --dry-run`; this
repository does not publish automatically.

## Build and installers

```bash
dartloom build windows
dartloom package windows exe
dartloom package windows zip
dartloom package windows msix
dartloom package linux deb
dartloom package linux rpm
```

`dartloom package windows exe` uses Inno Setup's `iscc.exe`. Install Inno Setup
6 and add its install directory to PATH.

The portable ZIP target does not require Inno Setup. Linux DEB/RPM packaging
must run on Linux.
macOS DMG/PKG, iOS IPA, Android installer packaging, and web installers are not
currently supported. This installer limitation is separate from capability
platform support.

## Repository development

The repository root is orchestration-only; it is not an installable Dart
package. The CLI is `cli/dartloom_cli`, contracts and adapters are under
`packages`, and generated apps depend only on selected packages.
